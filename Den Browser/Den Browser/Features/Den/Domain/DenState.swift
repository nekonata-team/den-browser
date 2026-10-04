import Foundation

struct DenState: Codable, Equatable {
    var desks: [DeskState]
    var focusedDeskID: UUID
    var drawerItems: [DrawerItem]

    init(
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        desks = try container.decode([DeskState].self, forKey: .desks)
        focusedDeskID = try container.decode(UUID.self, forKey: .focusedDeskID)
        drawerItems = try container.decodeIfPresent([DrawerItem].self, forKey: .drawerItems) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(desks, forKey: .desks)
        try container.encode(focusedDeskID, forKey: .focusedDeskID)
        if !drawerItems.isEmpty {
            try container.encode(drawerItems, forKey: .drawerItems)
        }
    }

    static var sample: DenState {
        makeInitial()
    }

    static func makeInitial() -> DenState {
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
