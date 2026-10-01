import SFSafeSymbols
import SwiftUI

enum DeskPresetSelection: Hashable {
    case builtIn(BuiltInDeskPreset)
    case personal(UUID)
    case newDesk(label: String)
}

struct DeskPresetPicker: View {
    let profileColor: Color
    let initialSelection: DeskPresetSelection
    @Binding var query: String
    @Binding var isManagementPresented: Bool
    let allowsEmptyPreset: Bool
    let isSearchFocused: FocusState<Bool>.Binding
    let onConfirm: (DeskPresetSelection) -> Void

    @Environment(DenStore.self) private var store
    @State private var scrollPosition = ScrollPosition()
    @State private var selection: DeskPresetSelection
    @State private var preservesSelectionAfterManagement = false

    init(
        profileColor: Color,
        initialSelection: DeskPresetSelection,
        query: Binding<String>,
        isManagementPresented: Binding<Bool>,
        allowsEmptyPreset: Bool,
        isSearchFocused: FocusState<Bool>.Binding,
        onConfirm: @escaping (DeskPresetSelection) -> Void
    ) {
        self.profileColor = profileColor
        self.initialSelection = initialSelection
        self._query = query
        self._isManagementPresented = isManagementPresented
        self.allowsEmptyPreset = allowsEmptyPreset
        self.isSearchFocused = isSearchFocused
        self.onConfirm = onConfirm
        self._selection = State(initialValue: initialSelection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField(
                        text: $query,
                        prompt: Text("Filter presets")
                    ) {
                        Text("Search Desk Presets")
                    }
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .focused(isSearchFocused)
                    .onSubmit { TextInputComposition.performUnlessActive(confirmSelection) }
                    .onKeyPress(phases: .down) { keyPress in
                        guard
                            keyPress.key == .tab,
                            !keyPress.modifiers.contains(.shift),
                            !TextInputComposition.isActive
                        else {
                            return .ignored
                        }
                        confirmSelection()
                        return .handled
                    }
                    Button {
                        isSearchFocused.wrappedValue = false
                        isManagementPresented = true
                    } label: {
                        Image(systemSymbol: .sliderHorizontal3)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.deskPresets.isEmpty)
                    .accessibilityLabel("Manage Presets")
                    .help("Manage Personal Desk Presets")
                }
                ScrollView {
                    presetChoices
                        .scrollTargetLayout()
                }
                .scrollPosition($scrollPosition, anchor: .center)
                .frame(maxHeight: 220)
            }
            .deskPresetArrowNavigation { moveSelection(by: $0) }

            DeskPresetPreview(boards: selectedBoards)

        }
        .onChange(of: store.deskPresets.map(\.id)) { _, ids in
            if case .personal(let id) = selection, !ids.contains(id) {
                preservesSelectionAfterManagement = false
                let fallback = matchingChoices.first?.selection ?? .builtIn(.empty)
                selection = fallback
            }
        }
        .onChange(of: query) { _, _ in
            preservesSelectionAfterManagement = false
            ensureValidSelection()
        }
        .onChange(of: isManagementPresented) { wasPresented, isPresented in
            if wasPresented && !isPresented { preservesSelectionAfterManagement = true }
        }
        .onChange(of: initialSelection) { _, newSelection in
            selection = newSelection
        }
        .onChange(of: selection) { _, newSelection in
            scrollPosition.scrollTo(id: scrollID(for: newSelection), anchor: .center)
        }
        .onAppear {
            selection = initialSelection
            ensureValidSelection()
        }
    }

    private var presetChoices: some View {
        VStack(alignment: .leading, spacing: 8) {
            if matchingChoices.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Built-in Presets")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(builtInChoices, id: \.selection) { choice in
                    choiceRow(choice)
                }

                if !personalChoices.isEmpty {
                    Text("My Presets")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    ForEach(personalChoices, id: \.selection) { choice in
                        choiceRow(choice)
                    }
                }
            } else {
                Text("Results")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(matchingChoices, id: \.selection) { choice in
                    choiceRow(choice, showsSource: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func choiceRow(_ choice: DeskPresetChoice, showsSource: Bool = false) -> some View {
        let isSelected = selection == choice.selection
        return Button {
            selection = choice.selection
            onConfirm(choice.selection)
        } label: {
            HStack {
                Image(systemSymbol: isSelected ? .chevronRight : .circle)
                    .foregroundStyle(isSelected ? profileColor : Color.secondary)
                    .frame(width: 16)
                Text(choice.label)
                Spacer()
                Text(
                    showsSource
                        ? "\(choice.sourceLabel) · \(boardCountLabel(choice.boards.count))"
                        : boardCountLabel(choice.boards.count)
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(selection == choice.selection ? "Active" : "")
        .padding(8)
        .denSelectionHighlight(isSelected, profileColor: profileColor, inactiveOpacity: 0.045)
        .id(scrollID(for: choice.selection))
    }

    private func scrollID(for selection: DeskPresetSelection) -> String {
        switch selection {
        case .builtIn(let preset): "builtIn:\(preset.rawValue)"
        case .personal(let id): "personal:\(id.uuidString)"
        case .newDesk(let label): "newDesk:\(label)"
        }
    }

    private var builtInChoices: [DeskPresetChoice] {
        BuiltInDeskPreset.allCases.filter { allowsEmptyPreset || $0 != .empty }.map {
            DeskPresetChoice(selection: .builtIn($0), label: $0.label, boards: $0.boards, sourceLabel: "Built-in")
        }
    }

    private var personalChoices: [DeskPresetChoice] {
        store.deskPresets.map {
            DeskPresetChoice(
                selection: .personal($0.id), label: $0.label, boards: $0.boards, sourceLabel: "My Preset")
        }
    }

    private var allChoices: [DeskPresetChoice] {
        builtInChoices + personalChoices
    }

    private var matchingChoices: [DeskPresetChoice] {
        let matches = DeskPresetSearch.matchingChoices(
            allChoices: allChoices,
            query: query,
            allowsEmptyPreset: allowsEmptyPreset
        )
        guard
            preservesSelectionAfterManagement,
            case .personal(let id) = selection,
            !matches.contains(where: { $0.selection == selection }),
            let selectedChoice = allChoices.first(where: { $0.selection == .personal(id) })
        else { return matches }
        return [selectedChoice] + matches
    }

    private var selectedBoards: [DeskPresetBoard] {
        switch selection {
        case .personal(let id):
            store.deskPresets.first(where: { $0.id == id })?.boards ?? []
        case .builtIn(let preset):
            preset.boards
        case .newDesk:
            []
        }
    }

    private func moveSelection(by offset: Int) {
        guard
            let nextSelection = DeskPresetSelectionNavigation.next(
                selection,
                among: matchingChoices.map(\.selection),
                by: offset
            )
        else { return }
        selection = nextSelection
    }

    private func confirmSelection() {
        guard
            let choice = matchingChoices.first(where: { $0.selection == selection })
                ?? matchingChoices.first
        else { return }
        onConfirm(choice.selection)
    }

    private func ensureValidSelection() {
        guard let first = matchingChoices.first else { return }
        if matchingChoices.count == 1 || !matchingChoices.contains(where: { $0.selection == selection }) {
            selection = first.selection
        }
    }

    private func boardCountLabel(_ count: Int) -> String {
        count == 1 ? "1 Board" : "\(count) Boards"
    }
}

struct DeskPresetChoice: Equatable {
    let selection: DeskPresetSelection
    let label: String
    let boards: [DeskPresetBoard]
    let sourceLabel: String
}

enum DeskPresetSelectionNavigation {
    static func next<Value: Equatable>(_ selection: Value?, among values: [Value], by offset: Int) -> Value? {
        guard !values.isEmpty else { return nil }
        let currentIndex =
            selection.flatMap { value in values.firstIndex(of: value) } ?? (offset > 0 ? -1 : values.count)
        return values[min(max(currentIndex + offset, 0), values.count - 1)]
    }
}

private struct DeskPresetArrowNavigation: ViewModifier {
    let isEditing: Bool
    let moveSelection: (Int) -> Void

    func body(content: Content) -> some View {
        content
            .onKeyPress(.upArrow) { handle(-1) }
            .onKeyPress(.downArrow) { handle(1) }
    }

    private func handle(_ offset: Int) -> KeyPress.Result {
        guard !isEditing, !TextInputComposition.isActive else { return .ignored }
        moveSelection(offset)
        return .handled
    }
}

extension View {
    func deskPresetArrowNavigation(isEditing: Bool = false, moveSelection: @escaping (Int) -> Void) -> some View {
        modifier(DeskPresetArrowNavigation(isEditing: isEditing, moveSelection: moveSelection))
    }
}

enum DeskPresetSearch {
    static func matchingChoices(
        allChoices: [DeskPresetChoice],
        query: String,
        allowsEmptyPreset: Bool
    ) -> [DeskPresetChoice] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return allChoices }

        var ranked: [(choice: DeskPresetChoice, score: Int, index: Int)] = []
        for (index, choice) in allChoices.enumerated() {
            if let score = score(
                query: trimmedQuery,
                label: choice.label,
                boards: choice.boards
            ) {
                ranked.append((choice, score, index))
            }
        }
        ranked.sort { lhs, rhs in
            lhs.score == rhs.score ? lhs.index < rhs.index : lhs.score < rhs.score
        }
        let matchingChoices = ranked.map(\.choice)
        guard allowsEmptyPreset else { return matchingChoices }
        return matchingChoices + [
            DeskPresetChoice(
                selection: .newDesk(label: trimmedQuery),
                label: "Create \"\(trimmedQuery)\"",
                boards: [],
                sourceLabel: "Empty Desk"
            )
        ]
    }

    static func score(query: String, label: String, boards: [DeskPresetBoard]) -> Int? {
        let tokens = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return 0 }

        let fields =
            [(label, 0)]
            + boards.flatMap { board -> [(String, Int)] in
                var fields = [(board.label, 1_000)]
                if let customLabel = board.customLabel {
                    fields.append((customLabel, 1_000))
                }
                return fields
            }
            + boards.compactMap { board in
                board.initialSheetURL?.host(percentEncoded: false).map { ($0, 2_000) }
            }
            + boards.compactMap { board in
                board.terminalWorkingDirectory.map { ($0, 2_000) }
            }
            + boards.compactMap { board in
                board.zellijSessionName.map { ($0, 2_000) }
            }
            + boards.compactMap { board in
                board.zmxSessionName.map { ($0, 2_000) }
            }

        var total = 0
        for token in tokens {
            guard
                let best = fields.compactMap({ field, penalty in
                    fuzzyScore(query: token, candidate: field).map { $0 + penalty }
                }).min()
            else { return nil }
            total += best
        }
        return total
    }

    private static func fuzzyScore(query: String, candidate: String) -> Int? {
        let query = normalized(query)
        let candidate = normalized(candidate)
        guard !query.isEmpty else { return 0 }
        guard !candidate.isEmpty else { return nil }

        if candidate.hasPrefix(query) {
            return candidate.count - query.count
        }
        if let range = candidate.range(of: query) {
            return 100 + candidate.distance(from: candidate.startIndex, to: range.lowerBound)
        }

        var searchStart = candidate.startIndex
        var gaps = 0
        for character in query {
            guard let index = candidate[searchStart...].firstIndex(of: character) else { return nil }
            gaps += candidate.distance(from: searchStart, to: index)
            searchStart = candidate.index(after: index)
        }
        return 200 + gaps + candidate.count - query.count
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map(String.init)
            .joined()
    }
}

struct DeskPresetPreview: View {
    let boards: [DeskPresetBoard]

    var body: some View {
        if boards.isEmpty {
            Text("No Boards")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(Array(boards.enumerated()), id: \.offset) { _, board in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(board.customLabel ?? board.label)
                                .lineLimit(1)
                            Text(previewSubtitle(for: board))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text("\(Int(board.width.rounded())) pt")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(7)
                        .frame(
                            width: max(90, min(150, board.width / 4)),
                            alignment: .leading
                        )
                        .background(
                            Color.primary.opacity(0.055),
                            in: RoundedRectangle(cornerRadius: DenRadius.small, style: .continuous)
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func previewSubtitle(for board: DeskPresetBoard) -> String {
        guard case .inspection = board.content else {
            return board.initialSheetURL?.host(percentEncoded: false) ?? "Empty Board"
        }
        guard let targetBoardIndex = board.targetBoardIndex, boards.indices.contains(targetBoardIndex) else {
            return "Inspection Board"
        }
        let targetBoard = boards[targetBoardIndex]
        return "Inspection of \(targetBoard.customLabel ?? targetBoard.label)"
    }
}
