import Observation

@MainActor
@Observable
public final class InputMethodSettingsModel {
    @ObservationIgnored private let read: () -> Bool
    @ObservationIgnored private let write: (Bool) -> Void

    public init(read: @escaping () -> Bool, write: @escaping (Bool) -> Void) {
        self.read = read
        self.write = write
    }

    public var rememberBoardInputMethod: Bool { read() }
    public func setRememberBoardInputMethod(_ enabled: Bool) { write(enabled) }
}
