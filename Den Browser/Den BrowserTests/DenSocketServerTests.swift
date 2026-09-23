import Darwin
import Foundation
import Testing

@testable import Den_Browser

struct DenSocketServerTests {
    @Test func socketServerReceivesAndResponds() async throws {
        let tempSocketPath = temporarySocketPath()
        defer { unlink(tempSocketPath) }

        let server = DenSocketServer(socketPath: tempSocketPath)
        try server.start { incomingData in
            guard let request = try? JSONDecoder().decode(DenIPCRequest.self, from: incomingData) else {
                return (try? JSONEncoder().encode(DenIPCResponse.failure("decode error"))) ?? Data()
            }
            if request.command == .health {
                var responseData = (try? JSONEncoder().encode(DenIPCResponse.success())) ?? Data()
                responseData.append(UInt8(ascii: "\n"))
                return responseData
            }
            return (try? JSONEncoder().encode(DenIPCResponse.failure("unknown"))) ?? Data()
        }
        defer { server.stop() }

        // Give server a moment to start listening
        try await Task.sleep(for: .milliseconds(50))

        let socketDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        #expect(socketDescriptor >= 0)
        defer { close(socketDescriptor) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = tempSocketPath.utf8CString
        withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
            pathBytes.withUnsafeBytes { source in
                buffer.copyMemory(from: source)
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddrPtr in
                connect(socketDescriptor, sockAddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        #expect(connectResult == 0)

        var requestData = try JSONEncoder().encode(DenIPCRequest(command: .health))
        requestData.append(UInt8(ascii: "\n"))

        requestData.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            _ = send(socketDescriptor, base, rawBuffer.count, MSG_NOSIGNAL)
        }

        var responseData = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        for _ in 0..<10 {
            let readBytes = read(socketDescriptor, &buffer, buffer.count)
            if readBytes > 0 {
                responseData.append(buffer, count: readBytes)
                if responseData.contains(UInt8(ascii: "\n")) { break }
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        let response = try JSONDecoder().decode(DenIPCResponse.self, from: responseData)
        #expect(response.isOk == true)
        #expect(response.message == nil)
    }

    @Test func stopCanBeCalledRepeatedlyWithoutClosingReusedFD() throws {
        let tempSocketPath = temporarySocketPath()
        defer { unlink(tempSocketPath) }

        let server = DenSocketServer(socketPath: tempSocketPath)
        try server.start { _ in Data() }

        // First stop
        server.stop()

        // Open a dummy pipe so that an FD is allocated
        var pipeFDs: [Int32] = [-1, -1]
        let pipeResult = pipe(&pipeFDs)
        #expect(pipeResult == 0)
        defer {
            if pipeFDs[0] >= 0 { close(pipeFDs[0]) }
            if pipeFDs[1] >= 0 { close(pipeFDs[1]) }
        }

        // Second stop: MUST NOT close pipeFDs
        server.stop()
        // Third stop: idempotent
        server.stop()

        // Verify the pipe FDs remain open and valid
        let readFlags = fcntl(pipeFDs[0], F_GETFL)
        let writeFlags = fcntl(pipeFDs[1], F_GETFL)
        #expect(readFlags >= 0)
        #expect(writeFlags >= 0)
    }

    @Test func serverRestartMaintainsConnectivity() async throws {
        let tempSocketPath = temporarySocketPath()
        defer { unlink(tempSocketPath) }

        let server = DenSocketServer(socketPath: tempSocketPath)
        let healthHandler: @Sendable (Data) async -> Data = { incomingData in
            guard let request = try? JSONDecoder().decode(DenIPCRequest.self, from: incomingData),
                request.command == .health
            else {
                return (try? JSONEncoder().encode(DenIPCResponse.failure("unknown"))) ?? Data()
            }
            var responseData = (try? JSONEncoder().encode(DenIPCResponse.success())) ?? Data()
            responseData.append(UInt8(ascii: "\n"))
            return responseData
        }

        try server.start(handler: healthHandler)
        try await Task.sleep(for: .milliseconds(50))
        let firstSuccess = await sendHealthCheck(to: tempSocketPath)
        #expect(firstSuccess == true)

        // Restart: older cancelHandler only closes its own FD, does not unlink new generation's socket
        server.stop()
        try server.start(handler: healthHandler)

        try await Task.sleep(for: .milliseconds(50))
        let secondSuccess = await sendHealthCheck(to: tempSocketPath)
        #expect(secondSuccess == true)

        server.stop()
        #expect(!FileManager.default.fileExists(atPath: tempSocketPath))
    }

    @Test func clientDisconnectBeforeResponseDoesNotCrashServer() async throws {
        let tempSocketPath = temporarySocketPath()
        defer { unlink(tempSocketPath) }

        let server = DenSocketServer(socketPath: tempSocketPath)
        try server.start { _ in
            try? await Task.sleep(for: .milliseconds(50))
            var responseData = (try? JSONEncoder().encode(DenIPCResponse.success())) ?? Data()
            responseData.append(UInt8(ascii: "\n"))
            return responseData
        }

        try await Task.sleep(for: .milliseconds(20))

        // Connect and send valid request, then immediately close FD before server replies
        let clientFD = try #require(connectClient(to: tempSocketPath))
        let requestData = (try? JSONEncoder().encode(DenIPCRequest(command: .health))) ?? Data()
        var packet = requestData
        packet.append(UInt8(ascii: "\n"))
        _ = packet.withUnsafeBytes { raw in
            send(clientFD, raw.baseAddress!, raw.count, MSG_NOSIGNAL)
        }
        close(clientFD)

        // Wait for server's handler to attempt writing to closed FD
        try await Task.sleep(for: .milliseconds(100))

        // Subsequent requests must succeed (server did not crash on SIGPIPE/EPIPE)
        let successAfterDisconnect = await sendHealthCheck(to: tempSocketPath)
        #expect(successAfterDisconnect == true)

        server.stop()
    }

    @Test func incompleteRequestWithoutNewlineIsIgnored() async throws {
        let tempSocketPath = temporarySocketPath()
        defer { unlink(tempSocketPath) }

        let server = DenSocketServer(socketPath: tempSocketPath)
        try server.start { _ in
            var responseData = (try? JSONEncoder().encode(DenIPCResponse.success())) ?? Data()
            responseData.append(UInt8(ascii: "\n"))
            return responseData
        }

        try await Task.sleep(for: .milliseconds(20))

        if let clientFD = connectClient(to: tempSocketPath) {
            let partial = Data("{\"command\":\"health\"".utf8)
            _ = partial.withUnsafeBytes { raw in
                send(clientFD, raw.baseAddress!, raw.count, MSG_NOSIGNAL)
            }
            close(clientFD)
        }

        try await Task.sleep(for: .milliseconds(50))

        let success = await sendHealthCheck(to: tempSocketPath)
        #expect(success == true)

        server.stop()
    }

    private func connectClient(to socketPath: String) -> Int32? {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            close(descriptor)
            return nil
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
            pathBytes.withUnsafeBytes { source in
                buffer.copyMemory(from: source)
            }
        }

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddrPtr in
                connect(descriptor, sockAddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            close(descriptor)
            return nil
        }
        return descriptor
    }

    private func sendHealthCheck(to socketPath: String) async -> Bool {
        guard let socketDescriptor = connectClient(to: socketPath) else { return false }
        defer { close(socketDescriptor) }

        guard var requestData = try? JSONEncoder().encode(DenIPCRequest(command: .health)) else { return false }
        requestData.append(UInt8(ascii: "\n"))

        let writeSuccess = requestData.withUnsafeBytes { rawBuffer -> Bool in
            guard let base = rawBuffer.baseAddress else { return false }
            return send(socketDescriptor, base, rawBuffer.count, MSG_NOSIGNAL) > 0
        }
        guard writeSuccess else { return false }

        var responseData = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        for _ in 0..<10 {
            let readBytes = read(socketDescriptor, &buffer, buffer.count)
            if readBytes > 0 {
                responseData.append(buffer, count: readBytes)
                if responseData.contains(UInt8(ascii: "\n")) { break }
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        guard let response = try? JSONDecoder().decode(DenIPCResponse.self, from: responseData) else { return false }
        return response.isOk
    }

    private func temporarySocketPath() -> String {
        "/tmp/den-t-\(UUID().uuidString.prefix(8)).sock"
    }
}
