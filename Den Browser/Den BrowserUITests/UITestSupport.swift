import Darwin
import XCTest

final class UITestProcessLock {
    private let handle: FileHandle

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "dev.nekonata.denbrowser.ui-tests.lock")
        _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forUpdating: url)
        guard flock(handle.fileDescriptor, LOCK_EX) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    deinit {
        flock(handle.fileDescriptor, LOCK_UN)
        try? handle.close()
    }
}

func uiTestDefaultsSuiteName(runID: String) -> String {
    "dev.nekonata.denbrowser.ui-testing.\(runID)"
}

extension XCUIElement {
    // Avoid XCTest's initial polling delay when the expected state already holds.
    func waitUntilExists(timeout: TimeInterval) -> Bool {
        exists || waitForExistence(timeout: timeout)
    }

    func waitUntilAbsent(timeout: TimeInterval) -> Bool {
        !exists || waitForNonExistence(timeout: timeout)
    }
}

@MainActor
func uiTestApplication() -> XCUIApplication {
    XCUIApplication()
}
