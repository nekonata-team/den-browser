import Darwin
import Foundation
import Testing

@testable import Den_Browser

struct DenSocketServerTests {
    @Test func socketServerReceivesAndResponds() async throws {
        let tempSocketPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-den-\(UUID().uuidString).sock").path
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
            _ = write(socketDescriptor, base, rawBuffer.count)
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
}
