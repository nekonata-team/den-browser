import Foundation

public struct DenState: Codable, Equatable {
    public var desks: [DeskState]
    public var focusedDeskID: UUID
    public var drawerItems: [DrawerItem]

    public init(
        desks: [DeskState],
        focusedDeskID: UUID,
        drawerItems: [DrawerItem] = []
    ) {
        self.desks = desks
        self.focusedDeskID = focusedDeskID
        self.drawerItems = drawerItems
    }

    private enum CodingKeys: String, CodingKey {
        case desks, focusedDeskID, drawerItems
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        desks = try container.decode([DeskState].self, forKey: .desks)
        focusedDeskID = try container.decode(UUID.self, forKey: .focusedDeskID)
        drawerItems = try container.decodeIfPresent([DrawerItem].self, forKey: .drawerItems) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(desks, forKey: .desks)
        try container.encode(focusedDeskID, forKey: .focusedDeskID)
        if !drawerItems.isEmpty {
            try container.encode(drawerItems, forKey: .drawerItems)
        }
    }

    public static var sample: DenState {
        makeInitial()
    }

    public static func makeInitial() -> DenState {
        let desk = DeskState(
            label: "Main",
            boards: []
        )
        return DenState(
            desks: [desk],
            focusedDeskID: desk.id
        )
    }
}
