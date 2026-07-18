import SwiftUI

enum DeskPresetSelection: Hashable {
    case builtIn(BuiltInDeskPreset)
    case personal(UUID)
}

struct DeskPresetPicker: View {
    @Binding var selection: DeskPresetSelection
    @Binding var query: String
    @Binding var isManaging: Bool
    let isSearchFocused: FocusState<Bool>.Binding
    let onConfirm: (DeskPresetSelection) -> Void

    @Environment(DenStore.self) private var store
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if isManaging {
                    Button(store.isDeskPresetManagementPresented ? "Done" : "Back") {
                        if store.isDeskPresetManagementPresented {
                            store.hideNewDeskPanel()
                        } else {
                            isManaging = false
                        }
                    }
                    .buttonStyle(.plain)
                    Text("Manage Presets")
                        .font(.headline)
                }
                TextField("Search Desk Presets", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused(isSearchFocused)
                    .onSubmit(confirmSelection)
                    .onKeyPress(.upArrow) {
                        guard !isManaging else { return .ignored }
                        moveSelection(by: -1)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        guard !isManaging else { return .ignored }
                        moveSelection(by: 1)
                        return .handled
                    }
                    .onKeyPress(phases: .down) { keyPress in
                        guard !isManaging, keyPress.key == .tab, !keyPress.modifiers.contains(.shift) else {
                            return .ignored
                        }
                        confirmSelection()
                        return .handled
                    }
            }

            ScrollView {
                if isManaging {
                    personalPresets
                } else {
                    presetChoices
                }
            }
            .frame(maxHeight: 220)

            if !isManaging {
                DeskPresetPreview(boards: selectedBoards)

                HStack {
                    Spacer()
                    Button("Manage Presets…") { isManaging = true }
                        .buttonStyle(.plain)
                        .disabled(store.deskPresets.isEmpty)
                }
            }
        }
        .onChange(of: store.deskPresets.map(\.id)) { _, ids in
            if case .personal(let id) = selection, !ids.contains(id) {
                selection = .builtIn(.empty)
            }
        }
        .onChange(of: query) { _, _ in ensureValidSelection() }
        .onAppear { ensureValidSelection() }
    }

    private var presetChoices: some View {
        VStack(alignment: .leading, spacing: 8) {
            if matchingChoices.isEmpty {
                ContentUnavailableView.search(text: query)
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

    private var personalPresets: some View {
        VStack(spacing: 6) {
            if filteredPersonalPresets.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView("No Personal Desk Presets", systemImage: "bookmark")
                } else {
                    ContentUnavailableView.search(text: query)
                }
            } else {
                ForEach(filteredPersonalPresets) { preset in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.label)
                            Text(boardCountLabel(preset.boards.count))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            store.requestDeskPresetDeletion(preset.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Delete \(preset.label)")
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func choiceRow(_ choice: DeskPresetChoice, showsSource: Bool = false) -> some View {
        Button {
            selection = choice.selection
            onConfirm(choice.selection)
        } label: {
            HStack {
                Image(systemName: selection == choice.selection ? "chevron.right" : "circle")
                    .foregroundStyle(selection == choice.selection ? Color.accentColor : Color.secondary)
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
        .background(
            Color.primary.opacity(selection == choice.selection ? 0.11 : 0.045),
            in: RoundedRectangle(cornerRadius: 8))
    }

    private var builtInChoices: [DeskPresetChoice] {
        BuiltInDeskPreset.allCases.map {
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
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return allChoices }

        var ranked: [(choice: DeskPresetChoice, score: Int, index: Int)] = []
        for (index, choice) in allChoices.enumerated() {
            if let score = DeskPresetSearch.score(
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
        return ranked.map(\.choice)
    }

    private var filteredPersonalPresets: [PersonalDeskPreset] {
        guard !query.isEmpty else { return store.deskPresets }
        return store.deskPresets.filter {
            DeskPresetSearch.score(query: query, label: $0.label, boards: $0.boards) != nil
        }
    }

    private var selectedBoards: [DeskPresetBoard] {
        matchingChoices.first(where: { $0.selection == selection })?.boards ?? []
    }

    private func moveSelection(by offset: Int) {
        guard !isManaging, !matchingChoices.isEmpty else { return }
        let currentIndex = matchingChoices.firstIndex(where: { $0.selection == selection }) ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), matchingChoices.count - 1)
        selection = matchingChoices[nextIndex].selection
    }

    private func confirmSelection() {
        guard !isManaging,
            let choice = matchingChoices.first(where: { $0.selection == selection })
                ?? matchingChoices.first
        else { return }
        selection = choice.selection
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

private struct DeskPresetChoice {
    let selection: DeskPresetSelection
    let label: String
    let boards: [DeskPresetBoard]
    let sourceLabel: String
}

enum DeskPresetSearch {
    static func score(query: String, label: String, boards: [DeskPresetBoard]) -> Int? {
        let tokens = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return 0 }

        let fields =
            [(label, 0)]
            + boards.map { ($0.label, 1_000) }
            + boards.compactMap { board in
                URL(string: board.currentURLString)?.host(percentEncoded: false).map { ($0, 2_000) }
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
                            Text(board.label)
                                .lineLimit(1)
                            Text(URL(string: board.currentURLString)?.host(percentEncoded: false) ?? "Empty Board")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text("\(Int(board.width.rounded())) pt")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(7)
                        .frame(width: max(90, min(150, board.width / 4)), alignment: .leading)
                        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}
