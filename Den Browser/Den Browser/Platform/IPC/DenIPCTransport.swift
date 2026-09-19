import Darwin

nonisolated enum DenSocketOption {
    static func disableSIGPIPE(on fileDescriptor: Int32) {
        var nosigpipe: Int32 = 1
        setsockopt(fileDescriptor, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))
    }
}
