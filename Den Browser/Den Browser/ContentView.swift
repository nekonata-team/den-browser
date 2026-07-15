//
//  ContentView.swift
//  Den Browser
//
//  Created by 大澤弘明 on 2026/07/10.
//

import AppKit
import SwiftUI

struct ContentView: View {
    private let boardSpacing: CGFloat = 10
    private let boardHorizontalPadding: CGFloat = 10
    private let profileName: String?
    private let profileColor: Color

    @Environment(DenStore.self) private var store
    @State private var urlText = ""
    @State private var newDeskLabel = ""
    @State private var selectedDeskTemplate: DeskTemplate = .empty
    @State private var didAttemptDeskCreation = false
    @State private var focusedBoardScrollTask: Task<Void, Never>?
    @State private var didScrollToRestoredFocusedBoard = false
    @State private var resizingBoardID: UUID?
    @FocusState private var isOpenPanelFocused: Bool
    @FocusState private var isNewDeskLabelFocused: Bool

    init(profileName: String? = nil, profileColor: Color = .blue) {
        self.profileName = profileName
        self.profileColor = profileColor
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                DenBackground(isDenMode: store.isDenMode, profileColor: profileColor)

                if store.focusedDesk?.boards.isEmpty == false {
                    boardStrip(in: geometry.size)
                } else {
                    EmptyDenView {
                        store.showOpenBoardPanel()
                    }
                }

                if shouldShowDeskSwitcher {
                    deskSwitcher
                        .padding(.top, 12)
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

                if store.isKeyboardShortcutsPresented,
                    store.focusedDesk?.boards.isEmpty == false
                {
                    KeyboardShortcutsView(onClose: store.hideKeyboardShortcuts)
                        .padding(18)
                        .frame(width: 760, height: 560)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .transition(.scale(scale: 0.98).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.18), value: store.isOpenBoardPanelPresented)
            .animation(.snappy(duration: 0.18), value: store.isNewDeskPanelPresented)
            .animation(.snappy(duration: 0.18), value: store.isOverviewPresented)
            .animation(.snappy(duration: 0.18), value: store.isKeyboardShortcutsPresented)
            .animation(.snappy(duration: 0.18), value: store.isZenViewPresented)
            .overlay {
                if store.isDenMode {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.cyan.opacity(0.72), lineWidth: 1)
                        .padding(6)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(minWidth: 1100, minHeight: 720)
        .navigationTitle(titlebarTitle)
        .confirmationDialog(
            "Delete \(store.deskPendingDeletion?.label ?? "Desk")?",
            isPresented: Binding(
                get: { store.deskPendingDeletion != nil },
                set: { if !$0 { store.cancelDeskDeletion() } })
        ) {
            Button("Delete Desk", role: .destructive) {
                store.confirmDeskDeletion()
            }
            Button("Cancel", role: .cancel) {
                store.cancelDeskDeletion()
            }
        } message: {
            let boardCount = store.deskPendingDeletion?.boards.count ?? 0
            Text(
                boardCount == 1
                    ? "Its Board and Sheet Stack will be permanently deleted."
                    : "Its \(boardCount) Boards and their Sheet Stacks will be permanently deleted."
            )
        }
    }

    private var titlebarTitle: String {
        let profilePrefix = profileName.map { "\($0) · " } ?? ""
        guard store.isDenMode else { return profileName.map { "\($0) — Den Browser" } ?? "Den Browser" }
        return profilePrefix + (store.heldBoardLabel == nil ? "DEN MODE" : "DEN MODE · HELD")
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
                .tint(.clear)
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
                    Text(newDeskPanelDescription)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Create", action: createDesk)
                    .buttonStyle(.glassProminent)
                    .disabled(trimmedNewDeskLabel.isEmpty || !store.canCreateDesk)
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
            DispatchQueue.main.async {
                isNewDeskLabelFocused = true
            }
        }
        .onExitCommand {
            store.hideNewDeskPanel()
        }
    }

    private var trimmedNewDeskLabel: String {
        newDeskLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var newDeskPanelDescription: String {
        store.canCreateDesk ? "New desk opens after the focused desk" : "A Den can contain up to 10 desks"
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
        stateHasMultipleDesks && !store.isZenViewPresented
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
                Text("n in Den Mode")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
        }
        .padding(16)
        .frame(width: 520)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear {
            DispatchQueue.main.async {
                isOpenPanelFocused = true
            }
        }
        .onExitCommand {
            store.hideOpenBoardPanel()
        }
    }

    private func boardStrip(in size: CGSize) -> some View {
        let boards = store.focusedDesk?.boards ?? []
        let topInset: CGFloat = shouldShowDeskSwitcher ? 48 : 10
        let bottomInset: CGFloat = 10
        let boardHeight = max(420, size.height - topInset - bottomInset)
        let maximizedBoardWidth = max(280, size.width - boardHorizontalPadding * 2)
        let firstBoardWidth =
            boards.first.map {
                store.maximizedBoardID == $0.id ? maximizedBoardWidth : $0.width
            } ?? size.width
        let lastBoardWidth =
            boards.last.map {
                store.maximizedBoardID == $0.id ? maximizedBoardWidth : $0.width
            } ?? size.width
        let leadingPadding = max(boardHorizontalPadding, (size.width - firstBoardWidth) / 2)
        let trailingPadding = max(boardHorizontalPadding, (size.width - lastBoardWidth) / 2)

        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: boardSpacing) {
                    ForEach(boards) { board in
                        BoardView(
                            board: board,
                            isFocused: board.id == store.focusedDesk?.focusedBoardID,
                            runtime: store.runtime(for: board),
                            width: store.maximizedBoardID == board.id ? maximizedBoardWidth : board.width,
                            height: boardHeight,
                            isPointerFocusEnabled: isBoardPointerFocusEnabled,
                            onFocus: { store.focusBoard(board.id) },
                            onGoBack: { store.goBackInBoard(board.id) },
                            onGoForward: { store.goForwardInBoard(board.id) },
                            onClose: { store.closeBoard(board.id) }
                        )
                        .id(board.id)
                        .overlay(alignment: .trailing) {
                            if store.maximizedBoardID != board.id {
                                BoardResizeHandle(
                                    board: board,
                                    height: boardHeight,
                                    width: boardSpacing,
                                    onResizeStart: {
                                        resizingBoardID = board.id
                                        store.focusBoard(board.id)
                                    },
                                    onResize: { store.resizeBoard(board.id, to: $0) },
                                    onResizeEnd: {
                                        store.saveBoardWidths()
                                        resizingBoardID = nil
                                    }
                                )
                                .offset(x: boardSpacing)
                            }
                        }
                        .allowsHitTesting(isBoardPointerFocusEnabled)
                        .zIndex(1)
                    }
                }
                .padding(.leading, leadingPadding)
                .padding(.trailing, trailingPadding)
                .padding(.top, topInset)
                .padding(.bottom, bottomInset)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                guard !didScrollToRestoredFocusedBoard else { return }
                didScrollToRestoredFocusedBoard = true
                centerBoard(store.focusedDesk?.focusedBoardID, using: proxy, animated: false)
            }
            .onChange(of: store.focusedDesk?.focusedBoardID) { _, focusedBoardID in
                centerBoard(focusedBoardID, using: proxy)
            }
            .onChange(of: store.centerFocusedBoardRequest) { _, _ in
                centerBoard(store.focusedDesk?.focusedBoardID, using: proxy)
            }
        }
    }

    private func centerBoard(_ boardID: UUID?, using proxy: ScrollViewProxy, animated: Bool = true) {
        focusedBoardScrollTask?.cancel()
        guard resizingBoardID == nil, let boardID else { return }

        focusedBoardScrollTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }

            if animated {
                withAnimation(.snappy(duration: 0.22)) {
                    proxy.scrollTo(boardID, anchor: .center)
                }
            } else {
                proxy.scrollTo(boardID, anchor: .center)
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

private struct BoardResizeHandle: View {
    @State private var isHovering = false
    @State private var widthAtDragStart: Double?

    let board: BoardState
    let height: Double
    let width: Double
    let onResizeStart: () -> Void
    let onResize: (Double) -> Void
    let onResizeEnd: () -> Void

    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .overlay {
                Capsule()
                    .fill(Color.primary.opacity(0.38))
                    .frame(width: 2, height: 34)
                    .opacity(isHovering || widthAtDragStart != nil ? 1 : 0)
            }
            .onHover { isHovering in
                self.isHovering = isHovering
                (isHovering ? NSCursor.resizeLeftRight : NSCursor.arrow).set()
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if widthAtDragStart == nil {
                            widthAtDragStart = board.width
                            onResizeStart()
                        }
                        onResize((widthAtDragStart ?? board.width) + value.translation.width)
                    }
                    .onEnded { _ in
                        widthAtDragStart = nil
                        onResizeEnd()
                    }
            )
            .help("Drag to resize board")
            .accessibilityLabel("Resize \(board.label) board")
    }
}

#Preview {
    ContentView()
        .environment(DenStore())
}

private struct DenBackground: View {
    let isDenMode: Bool
    let profileColor: Color

    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.08, green: 0.10, blue: 0.12),
                Color(red: 0.15, green: 0.16, blue: 0.19),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(.cyan.opacity(isDenMode ? 0.22 : 0.12))
                .blur(radius: 120)
                .frame(width: 420, height: 280)
                .offset(x: -120, y: -80)
        }
        .overlay(alignment: .topTrailing) {
            Rectangle()
                .fill(profileColor.opacity(isDenMode ? 0.05 : 0.10))
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

            KeyboardShortcutsView()
                .padding(18)
                .frame(width: 760, height: 460)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Button("Open Board", action: openBoard)
                .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 24)
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
                        .background(
                            Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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

                }
            }
            .padding(10)
            .frame(width: 158, height: 96, alignment: .leading)
            .foregroundStyle(.primary)
            .background(
                Color.primary.opacity(isSelected ? 0.18 : 0.09),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected ? .cyan.opacity(0.86) : Color.primary.opacity(0.12),
                        lineWidth: isSelected ? 2 : 1)
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
