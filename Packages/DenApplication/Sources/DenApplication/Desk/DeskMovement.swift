public import DenDomain

public struct DeskMovement {
    private let reader: DenStateReader
    private let writer: DenStateWriter
    private let persist: ((DenState) -> Bool)?

    public init(reader: DenStateReader, writer: DenStateWriter, persist: ((DenState) -> Bool)? = nil) {
        self.reader = reader
        self.writer = writer
        self.persist = persist
    }

    public func beginDrag(_ id: DeskID) -> Bool {
        guard reader.snapshot.activeDrag == nil, reader.snapshot.den.desks.contains(where: { $0.id == id }) else {
            return false
        }
        writer.update { $0.activeDrag = .desk(id) }
        return true
    }

    public func preview(_ id: DeskID, to index: DeskIndex) {
        guard let source = reader.snapshot.den.desks.firstIndex(where: { $0.id == id }),
            reader.snapshot.den.desks.indices.contains(index.rawValue), source != index.rawValue
        else { return }
        writer.update {
            let desk = $0.den.desks.remove(at: source)
            $0.den.desks.insert(desk, at: index.rawValue)
        }
    }

    public func restoreOrder(_ ids: [DeskID]) {
        let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        writer.update { $0.den.desks.sort { (order[$0.id] ?? Int.max) < (order[$1.id] ?? Int.max) } }
    }

    public func finishDrag() {
        guard case .desk? = reader.snapshot.activeDrag else { return }
        writer.update { $0.activeDrag = nil }
        save()
    }

    public func move(_ id: DeskID, by delta: Int) {
        guard reader.snapshot.activeDrag == nil,
            let index = reader.snapshot.den.desks.firstIndex(where: { $0.id == id }),
            reader.snapshot.den.desks.indices.contains(index + delta)
        else { return }
        writer.update { $0.den.desks.swapAt(index, index + delta) }
        save()
    }

    private func save() {
        guard reader.snapshot.activeDrag == nil else { return }
        _ = persist?(reader.snapshot.den)
    }
}
