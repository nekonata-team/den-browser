import DenDomain
import DenPresentationModels
import DenViews
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
    var boardHeight: CGFloat = DenLayout.fallbackBoardHeight

    @Environment(DenController.self) private var controller
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
        boardHeight: CGFloat = DenLayout.fallbackBoardHeight,
        onConfirm: @escaping (DeskPresetSelection) -> Void
    ) {
        self.profileColor = profileColor
        self.initialSelection = initialSelection
        self._query = query
        self._isManagementPresented = isManagementPresented
        self.allowsEmptyPreset = allowsEmptyPreset
        self.isSearchFocused = isSearchFocused
        self.boardHeight = boardHeight
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
                    .disabled(controller.deskPresets.isEmpty)
                    .accessibilityLabel("Manage Presets")
                    .help("Manage Personal Desk Presets")
                }
                ScrollView {
                    presetChoices
                        .scrollTargetLayout()
                }
                .scrollPosition($scrollPosition, anchor: .center)
                .frame(maxHeight: DenPanelLayout.previewedListMaxHeight)
            }
            .deskPresetArrowNavigation { moveSelection(by: $0) }

            DeskPresetPreview(
                boards: selectedBoards,
                boardHeight: boardHeight,
                facingForBoard: { index, _ in
                    if case .personal(let id) = selection {
                        return controller.presetFacingStore.image(for: id, at: index)
                    }
                    return nil
                }
            )
        }
        .task(id: selection) {
            if case .personal(let id) = selection {
                await controller.presetFacingStore.loadFacings(for: id, boardCount: selectedBoards.count)
            }
        }
        .onChange(of: controller.deskPresets.map(\.id)) { _, ids in
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
        .denSelectionHighlight(isSelected, profileColor: profileColor, showsInactiveBackground: true)
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
        controller.deskPresets.map {
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
            controller.deskPresets.first(where: { $0.id == id })?.boards ?? []
        case .builtIn(let preset):
            preset.boards
        case .newDesk:
            []
        }
    }

    private func moveSelection(by offset: Int) {
        guard
            let nextSelection = SelectionNavigation.next(
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
    private static let cardHeight: CGFloat = DenPanelLayout.presetFacingHeight
    private static let boardSpacing: CGFloat = 6
    private static let sideBoardSpacing: CGFloat = 3

    let boards: [DeskPresetBoard]
    var boardHeight: CGFloat = DenLayout.fallbackBoardHeight
    var facingForBoard: ((Int, DeskPresetBoard) -> NSImage?)?

    var body: some View {
        if boards.isEmpty {
            Text("No Boards")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(boards.enumerated()), id: \.offset) { index, board in
                        let isAttachedSideBoard =
                            index > 0 && board.targetBoardIndex == BoardIndex(rawValue: index - 1)
                        let leadingSpacing: CGFloat =
                            index == 0
                            ? 0
                            : (isAttachedSideBoard ? Self.sideBoardSpacing : Self.boardSpacing)
                        DeskPresetBoardFacing(
                            board: board,
                            boardHeight: boardHeight,
                            facingHeight: Self.cardHeight,
                            facing: facingForBoard?(index, board)
                        )
                        .padding(.leading, leadingSpacing)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}
