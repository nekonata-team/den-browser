import Foundation

protocol DemoScenario {
    static var name: String { get }
    @MainActor func initialProfileURL(directory: URL) throws -> URL?
    func prepare(context: inout DemoContext) throws
    func run(context: inout DemoContext) throws
}

extension DemoScenario {
    @MainActor func initialProfileURL(directory: URL) throws -> URL? { nil }
    func prepare(context: inout DemoContext) throws {}
}
