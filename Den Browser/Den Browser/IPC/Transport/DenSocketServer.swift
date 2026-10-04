import Darwin
import Foundation

nonisolated final class DenSocketServer: @unchecked Sendable {
    private var listeningSource: (any DispatchSourceRead)?
    private let socketPath: String
    private let queue = DispatchQueue(label: "dev.nekonata.den.ipc.server", qos: .userInitiated)

    static var defaultSocketPath: String { DenSocketPath.resolve() }

    init(socketPath: String = DenSocketServer.defaultSocketPath) {
        self.socketPath = socketPath
    }

    deinit {
        stop()
    }

    func start(handler: @escaping @Sendable (Data) async -> Data) throws {
        stop()

        let parentDir = URL(fileURLWithPath: socketPath).deletingLastPathComponent().path
        try FileManager.default.createDirectory(
            atPath: parentDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])

        unlink(socketPath)

        let socketDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        let flags = fcntl(socketDescriptor, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(socketDescriptor, F_SETFL, flags | O_NONBLOCK)
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            close(socketDescriptor)
            throw POSIXError(.ENAMETOOLONG)
        }

        withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
            pathBytes.withUnsafeBytes { source in
                buffer.copyMemory(from: source)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddrPtr in
                Darwin.bind(socketDescriptor, sockAddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            let err = errno
            close(socketDescriptor)
            throw POSIXError(POSIXErrorCode(rawValue: err) ?? .EIO)
        }

        chmod(socketPath, 0o600)

        guard Darwin.listen(socketDescriptor, 16) == 0 else {
            let err = errno
            close(socketDescriptor)
            unlink(socketPath)
            throw POSIXError(POSIXErrorCode(rawValue: err) ?? .EIO)
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: socketDescriptor, queue: queue)
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source, !source.isCancelled else { return }
            self.acceptConnections(listeningFD: socketDescriptor, handler: handler)
        }
        source.setCancelHandler { [socketDescriptor] in
            close(socketDescriptor)
        }
        source.resume()
        self.listeningSource = source
    }

    func stop() {
        if let source = listeningSource {
            listeningSource = nil
            source.cancel()
            unlink(socketPath)
        }
    }

    private func acceptConnections(listeningFD: Int32, handler: @escaping @Sendable (Data) async -> Data) {
        while true {
            let clientFD = Darwin.accept(listeningFD, nil, nil)
            guard clientFD >= 0 else { break }

            queue.async {
                Task {
                    await self.handleClient(clientFD: clientFD, handler: handler)
                }
            }
        }
    }

    private func handleClient(clientFD: Int32, handler: @escaping @Sendable (Data) async -> Data) async {
        defer { close(clientFD) }

        let flags = fcntl(clientFD, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(clientFD, F_SETFL, flags & ~O_NONBLOCK)
        }

        var buffer = [UInt8](repeating: 0, count: 65536)
        var receivedData = Data()

        while true {
            let bytesRead = Darwin.read(clientFD, &buffer, buffer.count)
            guard bytesRead > 0 else { break }
            receivedData.append(buffer, count: bytesRead)
            if receivedData.contains(UInt8(ascii: "\n")) {
                break
            }
        }

        guard !receivedData.isEmpty, receivedData.contains(UInt8(ascii: "\n")) else { return }

        let responseData = await handler(receivedData)

        responseData.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress, rawBuffer.count > 0 else { return }
            var written = 0
            while written < rawBuffer.count {
                let bytesWritten = Darwin.send(
                    clientFD, baseAddress.advanced(by: written), rawBuffer.count - written, MSG_NOSIGNAL)
                guard bytesWritten > 0 else { break }
                written += bytesWritten
            }
        }
    }
}
