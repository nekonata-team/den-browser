import XCTest

protocol BDD {}

extension BDD {
    @MainActor
    func given(_ description: String, _ body: () -> Void) {
        bddStep("Given: \(description)", body)
    }

    @MainActor
    func when(_ description: String, _ body: () -> Void) {
        bddStep("When: \(description)", body)
    }

    @MainActor
    func then(_ description: String, _ body: () -> Void) {
        bddStep("Then: \(description)", body)
    }

    @MainActor
    private func bddStep(_ name: String, _ body: () -> Void) {
        XCTContext.runActivity(named: name) { _ in
            body()
        }
    }
}
