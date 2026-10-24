public import DenDomain

public struct DeskLifecycle {
    public enum Notice {
        case presentCreatedDesk(DeskID)
        case didCreateDesk
        case willReplace([BoardState])
        case didReplace(deskID: DeskID, removedBoards: [BoardState])
        case willDelete(desk: DeskState, replacementDeskID: DeskID, wasPresented: Bool)
        case didDelete(desk: DeskState, wasPresented: Bool)
    }

    private let store: DenStateReader
    private let writer: DenStateWriter
    private let persist: ((DenState) -> Bool)?

    public init(store: DenStateReader, writer: DenStateWriter, persist: ((DenState) -> Bool)? = nil) {
        self.store = store
        self.writer = writer
        self.persist = persist
    }

    public var canCreate: Bool { store.snapshot.den.desks.count < DeskCreation.maximumDeskCount }

    public func canDelete(_ id: DeskID, isAvailable: (DeskID) -> Bool) -> Bool {
        DeskDeletion.delete(id, from: store.snapshot.den.desks, isAvailable: isAvailable) != nil
    }

    @discardableResult
    public func create(
        label: String, boards: [DeskPresetBoard], focusedBoardIndex: BoardIndex?,
        presentedDeskID: DeskID, after deskID: DeskID? = nil, focus: Bool = true, notify: (Notice) -> Void
    ) -> DeskState? {
        guard
            let result = DeskCreation.create(
                label: label, presetBoards: boards, focusedBoardIndex: focusedBoardIndex,
                in: store.snapshot.den.desks, presentedDeskID: deskID ?? presentedDeskID)
        else { return nil }
        writer.update { $0.den.desks = result.desks }
        if focus { notify(.presentCreatedDesk(result.createdDesk.id)) }
        save()
        notify(.didCreateDesk)
        return result.createdDesk
    }

    public func duplicate(
        _ id: DeskID, presentedDeskID: DeskID, notify: (Notice) -> Void
    ) -> (source: DeskState, copy: DeskState)? {
        guard let source = store.snapshot.den.desks.first(where: { $0.id == id }) else { return nil }
        let preset = PersonalDeskPreset(label: source.label, desk: source)
        guard
            let copy = create(
                label: source.label, boards: preset.boards, focusedBoardIndex: preset.focusedBoardIndex,
                presentedDeskID: presentedDeskID, after: source.id, notify: notify)
        else { return nil }
        return (source, copy)
    }

    @discardableResult
    public func replace(
        _ id: DeskID, label: String, boards: [DeskPresetBoard], focusedBoardIndex: BoardIndex?,
        notify: (Notice) -> Void
    ) -> Bool {
        guard
            let result = DeskReplacement.replace(
                id, label: label, presetBoards: boards, focusedBoardIndex: focusedBoardIndex,
                in: store.snapshot.den.desks)
        else { return false }
        notify(.willReplace(result.removedBoards))
        writer.update { $0.den.desks[result.deskIndex.rawValue] = result.desk }
        notify(.didReplace(deskID: id, removedBoards: result.removedBoards))
        cancelDrag(removing: Set(result.removedBoards.map(\.id)))
        save()
        return true
    }

    @discardableResult
    public func delete(
        _ id: DeskID, presentedDeskID: DeskID, isAvailable: (DeskID) -> Bool, notify: (Notice) -> Void
    ) -> Bool {
        guard let result = DeskDeletion.delete(id, from: store.snapshot.den.desks, isAvailable: isAvailable) else {
            return false
        }
        let wasPresented = presentedDeskID == id
        notify(
            .willDelete(
                desk: result.removedDesk, replacementDeskID: result.replacementDeskID, wasPresented: wasPresented))
        writer.update { $0.den.desks = result.desks }
        notify(.didDelete(desk: result.removedDesk, wasPresented: wasPresented))
        cancelDrag(removing: Set(result.removedDesk.boards.map(\.id)), deskID: id)
        save()
        return true
    }

    private func cancelDrag(removing boardIDs: Set<BoardID>, deskID: DeskID? = nil) {
        switch store.snapshot.activeDrag {
        case .board(let id) where boardIDs.contains(id): writer.update { $0.activeDrag = nil }
        case .desk(let id) where id == deskID: writer.update { $0.activeDrag = nil }
        default: break
        }
    }

    private func save() {
        guard store.snapshot.activeDrag == nil else { return }
        _ = persist?(store.snapshot.den)
    }
}
