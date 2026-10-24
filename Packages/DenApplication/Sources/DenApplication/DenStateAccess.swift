/// Synchronous access to caller-owned state.
///
/// The owner supplies isolation and lifetime.
/// These capabilities are not Sendable and must stay within the owner's execution context.
public struct DenStateReader {
    private let read: () -> DenSharedState

    public init(read: @escaping () -> DenSharedState) {
        self.read = read
    }

    public var snapshot: DenSharedState { read() }
}

public struct DenStateWriter {
    private let write: ((inout DenSharedState) -> Void) -> Void

    public init(write: @escaping ((inout DenSharedState) -> Void) -> Void) {
        self.write = write
    }

    public func update(_ mutation: (inout DenSharedState) -> Void) {
        write(mutation)
    }
}
