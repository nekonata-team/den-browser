import Foundation

public enum BrowsingDataCategory: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case cookies
    case cache
    case localData

    public var id: Self { self }

}
