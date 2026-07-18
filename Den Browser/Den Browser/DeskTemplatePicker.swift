import SwiftUI

enum DeskTemplateSelection: Hashable {
    case builtIn(BuiltInDeskTemplate)
    case personal(UUID)
}

struct DeskTemplatePicker: View {
    @Binding var selection: DeskTemplateSelection
    @Binding var query: String
    @Binding var isManaging: Bool
    let isSearchFocused: FocusState<Bool>.Binding
    let onConfirm: (DeskTemplateSelection) -> Void

    @Environment(DenStore.self) private var store
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if isManaging {
                    Button(store.isDeskTemplateManagementPresented ? "Done" : "Back") {
                        if store.isDeskTemplateManagementPresented {
                            store.hideNewDeskPanel()
                        } else {
                            isManaging = false
                        }
                    }
                    .buttonStyle(.plain)
                    Text("Manage Templates")
                        .font(.headline)
                }
                TextField("Search Desk Templates", text: $query)
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
                    personalTemplates
                } else {
                    templateChoices
                }
            }
            .frame(maxHeight: 220)

            if !isManaging {
                DeskTemplatePreview(boards: selectedBoards)

                HStack {
                    Spacer()
                    Button("Manage Templates…") { isManaging = true }
                        .buttonStyle(.plain)
                        .disabled(store.deskTemplates.isEmpty)
                }
            }
        }
        .onChange(of: store.deskTemplates.map(\.id)) { _, ids in
            if case .personal(let id) = selection, !ids.contains(id) {
                selection = .builtIn(.empty)
            }
        }
        .onChange(of: query) { _, _ in ensureValidSelection() }
        .onAppear { ensureValidSelection() }
    }

    private var templateChoices: some View {
        VStack(alignment: .leading, spacing: 8) {
            if matchingChoices.isEmpty {
                ContentUnavailableView.search(text: query)
            } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Built-in Templates")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(builtInChoices, id: \.selection) { choice in
                    choiceRow(choice)
                }

                if !personalChoices.isEmpty {
                    Text("My Templates")
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

    private var personalTemplates: some View {
        VStack(spacing: 6) {
            if filteredPersonalTemplates.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView("No Personal Desk Templates", systemImage: "bookmark")
                } else {
                    ContentUnavailableView.search(text: query)
                }
            } else {
                ForEach(filteredPersonalTemplates) { template in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.label)
                            Text(boardCountLabel(template.boards.count))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            store.requestDeskTemplateDeletion(template.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Delete \(template.label)")
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func choiceRow(_ choice: DeskTemplateChoice, showsSource: Bool = false) -> some View {
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

    private var builtInChoices: [DeskTemplateChoice] {
        BuiltInDeskTemplate.allCases.map {
            DeskTemplateChoice(selection: .builtIn($0), label: $0.label, boards: $0.boards, sourceLabel: "Built-in")
        }
    }

    private var personalChoices: [DeskTemplateChoice] {
        store.deskTemplates.map {
            DeskTemplateChoice(
                selection: .personal($0.id), label: $0.label, boards: $0.boards, sourceLabel: "My Template")
        }
    }

    private var allChoices: [DeskTemplateChoice] {
        builtInChoices + personalChoices
    }

    private var matchingChoices: [DeskTemplateChoice] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return allChoices }

        var ranked: [(choice: DeskTemplateChoice, score: Int, index: Int)] = []
        for (index, choice) in allChoices.enumerated() {
            if let score = DeskTemplateSearch.score(
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

    private var filteredPersonalTemplates: [PersonalDeskTemplate] {
        guard !query.isEmpty else { return store.deskTemplates }
        return store.deskTemplates.filter {
            DeskTemplateSearch.score(query: query, label: $0.label, boards: $0.boards) != nil
        }
    }

    private var selectedBoards: [DeskTemplateBoard] {
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

private struct DeskTemplateChoice {
    let selection: DeskTemplateSelection
    let label: String
    let boards: [DeskTemplateBoard]
    let sourceLabel: String
}

enum DeskTemplateSearch {
    static func score(query: String, label: String, boards: [DeskTemplateBoard]) -> Int? {
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

struct DeskTemplatePreview: View {
    let boards: [DeskTemplateBoard]

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
