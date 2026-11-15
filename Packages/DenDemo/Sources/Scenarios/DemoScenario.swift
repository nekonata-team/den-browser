import Foundation

protocol DemoScenario {
    static var name: String { get }
    func initialProfileURL(directory: URL) throws -> URL?
    func prepare(context: inout DemoContext) throws
    func run(context: inout DemoContext) throws
}

extension DemoScenario {
    func initialProfileURL(directory: URL) throws -> URL? { nil }
    func prepare(context: inout DemoContext) throws {}
}
