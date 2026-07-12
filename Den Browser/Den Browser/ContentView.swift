//
//  ContentView.swift
//  Den Browser
//
//  Created by 大澤弘明 on 2026/07/10.
//

import SwiftUI

struct ContentView: View {
    private let boardSpacing: CGFloat = 10
    private let boardHorizontalPadding: CGFloat = 10

    @Environment(DenStore.self) private var store
    @State private var urlText = ""
    @State private var newDeskLabel = ""
    @State private var selectedDeskTemplate: DeskTemplate = .empty
    @State private var didAttemptDeskCreation = false
    @State private var focusedBoardScrollTask: Task<Void, Never>?
    @FocusState private var isOpenPanelFocused: Bool
    @FocusState private var isNewDeskLabelFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                DenBackground()

                if store.focusedDesk?.boards.isEmpty == false {
                    boardStrip(in: geometry.size)

                    if shouldShowDeskSwitcher {
                        deskSwitcher
                            .padding(.top, 12)
                    }
                } else {
                    EmptyDenView {
                        store.showOpenBoardPanel()
                    }
                }

                if store.isOpenBoardPanelPresented {
                    openBoardPanel(defaultBoardWidth: defaultBoardWidth(in: geometry.size))
                        .padding(.top, shouldShowDeskSwitcher ? 74 : 12)
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                }

                if store.isOverviewPresented {
                    OverviewView()
                        .padding(18)
                        .transition(.scale(scale: 0.98).combined(with: .opacity))
                }

                if store.isNewDeskPanelPresented {
                    newDeskPanel
                        .padding(.top, shouldShowDeskSwitcher ? 74 : 12)
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.18), value: store.isOpenBoardPanelPresented)
            .animation(.snappy(duration: 0.18), value: store.isNewDeskPanelPresented)
            .animation(.snappy(duration: 0.18), value: store.isOverviewPresented)
        }
        .frame(minWidth: 1100, minHeight: 720)
    }

    private var deskSwitcher: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(store.state.desks) { desk in
                            deskSwitcherButton(desk)
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .scrollIndicators(.hidden)
            .onChange(of: store.state.focusedDeskID) { _, deskID in
                withAnimation(.snappy(duration: 0.22)) {
                    proxy.scrollTo(deskID, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func deskSwitcherButton(_ desk: DeskState) -> some View {
        if desk.id == store.state.focusedDeskID {
            deskButton(desk)
                .buttonStyle(.glassProminent)
                .id(desk.id)
        } else {
            deskButton(desk)
                .buttonStyle(.glass)
                .id(desk.id)
        }
    }

    private func deskButton(_ desk: DeskState) -> some View {
        Button {
            store.focusDesk(desk.id)
        } label: {
            Text(desk.label)
                .lineLimit(1)
                .frame(maxWidth: 180)
        }
    }

    private var newDeskPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.stack.badge.plus")
                    .foregroundStyle(.secondary)

                TextField("Desk label", text: $newDeskLabel)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .medium))
                    .focused($isNewDeskLabelFocused)
                    .onSubmit(createDesk)
            }
            .frame(height: 38)

            Picker("Template", selection: $selectedDeskTemplate) {
                ForEach(DeskTemplate.allCases) { template in
                    Text(template.label).tag(template)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                if didAttemptDeskCreation && trimmedNewDeskLabel.isEmpty {
                    Text("Enter a desk label")
                        .foregroundStyle(.red)
                } else {
                    Text("New desk opens after the focused desk")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Create", action: createDesk)
                    .buttonStyle(.glassProminent)
                    .disabled(trimmedNewDeskLabel.isEmpty)
            }
            .font(.system(size: 12))
        }
        .padding(16)
        .frame(width: 520)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear {
            newDeskLabel = ""
            selectedDeskTemplate = .empty
            didAttemptDeskCreation = false
            isNewDeskLabelFocused = true
        }
        .onExitCommand {
            store.hideNewDeskPanel()
        }
    }

    private var trimmedNewDeskLabel: String {
        newDeskLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createDesk() {
        didAttemptDeskCreation = true
        guard !trimmedNewDeskLabel.isEmpty else { return }
        store.createDesk(label: newDeskLabel, template: selectedDeskTemplate)
        newDeskLabel = ""
        selectedDeskTemplate = .empty
        didAttemptDeskCreation = false
    }

    private var shouldShowDeskSwitcher: Bool {
        stateHasMultipleDesks
    }

    private var stateHasMultipleDesks: Bool {
        store.state.desks.count > 1
    }

    private func defaultBoardWidth(in size: CGSize) -> Double {
        (size.width - boardHorizontalPadding * 2 - boardSpacing) / 2
    }

    private func openBoardPanel(defaultBoardWidth: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "plus.rectangle.on.rectangle")
                    .foregroundStyle(.secondary)

                TextField("Open URL or search", text: $urlText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .medium))
                    .focused($isOpenPanelFocused)
                    .onSubmit {
                        openBoard(defaultBoardWidth: defaultBoardWidth)
                    }
            }
            .frame(height: 38)

            HStack(spacing: 12) {
                Text("New board opens to the right of the focused board")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("⌃⌥Space")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
        }
        .padding(16)
        .frame(width: 520)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear {
            isOpenPanelFocused = true
        }
        .onExitCommand {
            store.hideOpenBoardPanel()
        }
    }

    private func boardStrip(in size: CGSize) -> some View {
        let topInset: CGFloat = shouldShowDeskSwitcher ? 48 : 10
        let bottomInset: CGFloat = 10
        let boardHeight = max(420, size.height - topInset - bottomInset)

        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: boardSpacing) {
                    ForEach(store.focusedDesk?.boards ?? []) { board in
                        BoardView(
                            board: board,
                            isFocused: board.id == store.focusedDesk?.focusedBoardID,
                            isHeld: board.id == store.heldBoardID,
                            runtime: store.runtime(for: board),
                            height: boardHeight,
                            isPointerFocusEnabled: isBoardPointerFocusEnabled,
                            onFocus: { store.focusBoard(board.id) },
                            onGoBack: { store.goBackInBoard(board.id) },
                            onGoForward: { store.goForwardInBoard(board.id) }
                        )
                        .id(board.id)
                        .allowsHitTesting(isBoardPointerFocusEnabled)
                    }
                }
                .padding(.horizontal, boardHorizontalPadding)
                .padding(.top, topInset)
                .padding(.bottom, bottomInset)
            }
            .scrollIndicators(.hidden)
            .onChange(of: store.focusedDesk?.focusedBoardID) { _, focusedBoardID in
                focusedBoardScrollTask?.cancel()
                guard let focusedBoardID else { return }

                focusedBoardScrollTask = Task { @MainActor in
                    await Task.yield()
                    guard !Task.isCancelled else { return }

                    withAnimation(.snappy(duration: 0.22)) {
                        proxy.scrollTo(focusedBoardID, anchor: .center)
                    }
                }
            }
        }
    }

    private var isBoardPointerFocusEnabled: Bool {
        !store.isOpenBoardPanelPresented
            && !store.isNewDeskPanelPresented
            && !store.isOverviewPresented
    }

    private func openBoard(defaultBoardWidth: Double) {
        store.addBoard(urlString: urlText, preferredWidth: defaultBoardWidth)
        urlText = ""
    }
}

#Preview {
    ContentView()
        .environment(DenStore())
}

private struct DenBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.08, green: 0.10, blue: 0.12),
                Color(red: 0.15, green: 0.16, blue: 0.19)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(.cyan.opacity(0.12))
                .blur(radius: 120)
                .frame(width: 420, height: 280)
                .offset(x: -120, y: -80)
        }
        .overlay(alignment: .topTrailing) {
            Rectangle()
                .fill(.orange.opacity(0.10))
                .blur(radius: 140)
                .frame(width: 420, height: 280)
                .offset(x: 140, y: -90)
        }
        .ignoresSafeArea()
    }
}

private struct EmptyDenView: View {
    let openBoard: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text("Den Browser")
                    .font(.system(size: 28, weight: .semibold))

                Text("Open a board to start arranging web work.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                ShortcutRow(keys: "⌃⌥N", label: "New desk")
                ShortcutRow(keys: "⌃⌥Space", label: "Open board")
                ShortcutRow(keys: "⌃⌥O", label: "Overview")
                ShortcutRow(keys: "⌃⌥←/→", label: "Move between boards")
                ShortcutRow(keys: "⌃⌥↑/↓", label: "Move between desks")
                ShortcutRow(keys: "⌃⌥⇧←/→", label: "Move board")
                ShortcutRow(keys: "⌃⌥⇧↑/↓", label: "Move board to desk")
                ShortcutRow(keys: "⌃⌥[/]", label: "Back / forward sheet")
                ShortcutRow(keys: "⌘R", label: "Reload current sheet")
                ShortcutRow(keys: "⌃⌥-/;", label: "Resize board")
                ShortcutRow(keys: "⌃⌥W", label: "Close board")
                ShortcutRow(keys: "⌃⌥H", label: "Hold board")
                ShortcutRow(keys: "⌃⌥P", label: "Place held board")
                ShortcutRow(keys: "⌃⌥Return", label: "Duplicate sheet")
            }
            .padding(18)
            .frame(width: 360)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Button("Open Board", action: openBoard)
                .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 24)
    }
}

private struct ShortcutRow: View {
    let keys: String
    let label: String

    var body: some View {
        HStack {
            Text(keys)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)

            Text(label)
                .font(.system(size: 13))

            Spacer()
        }
    }
}

private struct OverviewView: View {
    @Environment(DenStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Overview")
                .font(.system(size: 17, weight: .semibold))

            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(store.state.desks) { desk in
                        deskRow(desk)
                    }
                }
                .padding(2)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button {
                store.hideOverview()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.glass)
            .padding(14)
        }
        .overlay {
            overviewKeyboardHandlers
                .frame(width: 0, height: 0)
                .opacity(0)
        }
        .onExitCommand {
            store.hideOverview()
        }
    }

    private func deskRow(_ desk: DeskState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(desk.label)
                    .font(.system(size: 13, weight: .semibold))

                if desk.id == store.overviewSelectionDeskID {
                    Circle()
                        .fill(.cyan)
                        .frame(width: 6, height: 6)
                }
            }
            .foregroundStyle(Color.primary.opacity(desk.id == store.overviewSelectionDeskID ? 0.96 : 0.58))

            HStack(alignment: .top, spacing: 10) {
                if desk.boards.isEmpty {
                    Text("Empty")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 150, height: 88)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    ForEach(desk.boards) { board in
                        overviewBoard(board, in: desk)
                    }
                }
            }
        }
    }

    private func overviewBoard(_ board: BoardState, in desk: DeskState) -> some View {
        let isSelected = desk.id == store.overviewSelectionDeskID && board.id == store.overviewSelectionBoardID
        let isHeld = board.id == store.heldBoardID

        return Button {
            store.selectBoardInOverview(board.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(board.label)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)

                Text(URL(string: board.currentURLString)?.host(percentEncoded: false) ?? board.currentURLString)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                HStack(spacing: 5) {
                    Capsule()
                        .fill(.secondary.opacity(0.35))
                        .frame(width: max(24, min(92, board.width / 9)), height: 5)

                    if isHeld {
                        Text("Held")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(10)
            .frame(width: 158, height: 96, alignment: .leading)
            .foregroundStyle(.primary)
            .background(Color.primary.opacity(isSelected ? 0.18 : 0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isHeld ? .orange.opacity(0.86) : (isSelected ? .cyan.opacity(0.86) : Color.primary.opacity(0.12)), lineWidth: isHeld || isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var overviewKeyboardHandlers: some View {
        Group {
            Button("Previous Board") {
                store.selectPreviousBoardInOverview()
            }
            .keyboardShortcut(.leftArrow, modifiers: [])

            Button("Next Board") {
                store.selectNextBoardInOverview()
            }
            .keyboardShortcut(.rightArrow, modifiers: [])

            Button("Previous Desk") {
                store.selectPreviousDeskInOverview()
            }
            .keyboardShortcut(.upArrow, modifiers: [])

            Button("Next Desk") {
                store.selectNextDeskInOverview()
            }
            .keyboardShortcut(.downArrow, modifiers: [])

            Button("Move Board Left") {
                store.moveOverviewSelectionBoardLeft()
            }
            .keyboardShortcut(.leftArrow, modifiers: [.shift])

            Button("Move Board Right") {
                store.moveOverviewSelectionBoardRight()
            }
            .keyboardShortcut(.rightArrow, modifiers: [.shift])

            Button("Move Board to Previous Desk") {
                store.moveOverviewSelectionBoardToPreviousDesk()
            }
            .keyboardShortcut(.upArrow, modifiers: [.shift])

            Button("Move Board to Next Desk") {
                store.moveOverviewSelectionBoardToNextDesk()
            }
            .keyboardShortcut(.downArrow, modifiers: [.shift])

            Button("Enter Focused Board") {
                store.enterOverviewSelection()
            }
            .keyboardShortcut(.return, modifiers: [])
        }
    }
}
