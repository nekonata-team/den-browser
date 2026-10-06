import DenDomain
import SFSafeSymbols
import SwiftUI

struct TutorialBoardView: View {
    @Environment(DenStore.self) private var store
    @Environment(DenViewModel.self) private var viewModel
    @Environment(DeskFilterViewModel.self) private var deskFilter
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    let board: BoardState
    let isFocused: Bool
    let isDragging: Bool
    let profileColor: Color
    let width: Double
    let height: Double
    let isPointerFocusEnabled: Bool
    let onFocus: () -> Void
    let onRemove: () -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Learn Den")
                                .font(.title2.weight(.semibold))
                            Text("Try a few actions to get comfortable with your Desk.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Button {
                                viewModel.showKeyboardShortcuts()
                            } label: {
                                Label("View all shortcuts", systemSymbol: .keyboard)
                            }
                            .buttonStyle(.borderless)
                            .font(.callout)
                            .padding(.top, 2)
                        }

                        VStack(spacing: 0) {
                            stepRow(
                                step: .openBoard,
                                title: "Create a Web Board",
                                detail: "Click + at the end of the Board Strip, then open a website or search."
                            )
                            Divider().padding(.leading, 42)
                            navigationStep
                            Divider().padding(.leading, 42)
                            stepRow(
                                step: .createDesk,
                                title: "Create a Desk",
                                detail: "Click + in the Desk Switcher to create a Desk, then select this Desk."
                            )
                        }
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(.primary.opacity(0.08))
                        }

                        if requiredTutorialSteps.allSatisfy({
                            board.tutorialCompletedSteps?.contains($0) == true
                        }) {
                            Label("You’re ready to explore Den.", systemSymbol: .checkmarkCircleFill)
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            VStack(spacing: 0) {
                                keyboardShortcutsStep
                                Divider().padding(.leading, 42)
                                stepRow(
                                    step: .terminalBoard,
                                    title: "Try a Terminal Board (optional)",
                                    detail: "Open a terminal Board with :terminal.",
                                    actionTitle: "Open Terminal",
                                    command: ":terminal",
                                    shortcutTokens: openBoardShortcutTokens
                                )
                            }
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(.primary.opacity(0.08))
                            }
                        }
                    }
                    .padding(geometry.size.width < 440 ? 16 : 24)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .topLeading)
                }
            }
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))
        .modifier(
            BoardSurfaceModifier(
                boardID: board.id,
                isFocused: isFocused,
                isDragging: isDragging,
                profileColor: profileColor,
                width: width,
                height: height,
                isFocusModeDeemphasized: viewModel.isFocusModePresented && !isFocused
                    && !deskFilter.isPresented,
                isFocusModeFocused: viewModel.isFocusModePresented && isFocused,
                differentiateWithoutColor: differentiateWithoutColor,
                shouldReduceMotion: DenMotion.shouldReduceMotion(
                    preference: preferences.motionPreference,
                    systemReduceMotion: systemReduceMotion
                )
            )
        )
    }

    private var header: some View {
        HStack(spacing: DenLayout.outerInset) {
            BoardDragHeader(
                board: board,
                isFocused: isFocused,
                isDragging: isDragging,
                isPointerFocusEnabled: isPointerFocusEnabled,
                onFocus: onFocus,
                onDragChanged: onDragChanged,
                onDragEnded: onDragEnded,
                onMoveLeft: {
                    store.focusBoard(board.id)
                    store.moveFocusedBoardLeft()
                },
                onMoveRight: {
                    store.focusBoard(board.id)
                    store.moveFocusedBoardRight()
                },
                leadingContent: {
                    Image(systemSymbol: .checklist)
                        .foregroundStyle(.secondary)
                }
            )
            Button(action: onRemove) {
                Image(systemSymbol: .xmark)
                    .frame(width: DenLayout.boardControlSize, height: DenLayout.boardControlSize)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
            .help("Remove Board")
            .accessibilityLabel("Remove Board")
        }
        .padding(.horizontal, DenLayout.chromeHorizontalPadding)
        .frame(height: DenLayout.boardHeaderHeight)
        .background(viewModel.isDenMode && isFocused ? profileColor.opacity(0.12) : Color.clear)
        .background(.regularMaterial)
        .modifier(BoardHeaderCenteringModifier(boardID: board.id, isEnabled: isPointerFocusEnabled))
    }

    private var keyboardShortcutsStep: some View {
        let step = TutorialBoardStep.keyboardShortcuts
        let status = stepState(step)
        let toggleBinding = preferences.shortcut(for: .toggleDenMode)

        return HStack(alignment: .top, spacing: 12) {
            stepStatus(step)
            VStack(alignment: .leading, spacing: 5) {
                Text("Explore Den Mode (optional)")
                    .font(.headline)
                if status == .current {
                    Text("Toggle Den Mode, then press ? to see the keyboard actions available there.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    shortcutHint("Toggle Den Mode", tokens: toggleBinding?.displayTokens ?? ["⌃", ","])
                    shortcutHint("Show shortcuts", tokens: ["?"])
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .opacity(status == .upcoming ? 0.48 : 1)
    }

    private var navigationStep: some View {
        let step = TutorialBoardStep.navigateBoards
        let status = stepState(step)
        let previousBinding = preferences.shortcut(for: .focusPreviousBoard)
        let nextBinding = preferences.shortcut(for: .focusNextBoard)

        return HStack(alignment: .top, spacing: 12) {
            stepStatus(step)
            VStack(alignment: .leading, spacing: 5) {
                Text("Move between Boards")
                    .font(.headline)
                if status == .current {
                    Text("Use these shortcuts to focus the previous or next Board.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    shortcutHint(
                        "Previous Board",
                        tokens: previousBinding?.displayTokens ?? ["←", "/", "h"])
                    shortcutHint(
                        "Next Board",
                        tokens: nextBinding?.displayTokens ?? ["→", "/", "l"])
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .opacity(status == .upcoming ? 0.48 : 1)
    }

    private func stepRow(
        step: TutorialBoardStep,
        title: String,
        detail: String,
        actionTitle: String? = nil,
        command: String? = nil,
        shortcutTokens: [String]? = nil
    ) -> some View {
        let status = stepState(step)
        return HStack(alignment: .top, spacing: 12) {
            stepStatus(step)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                if status == .current {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let command {
                        Text(command)
                            .font(.caption.monospaced())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                            .padding(.top, 2)
                    }
                    if let shortcutTokens {
                        shortcutHint("Shortcut", tokens: shortcutTokens)
                    }
                    if let actionTitle {
                        Button(actionTitle) {
                            store.focusBoard(board.id)
                            viewModel.showOpenBoardPanel(afterBoardID: board.id)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.top, 5)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .opacity(status == .upcoming ? 0.48 : 1)
    }

    private enum StepState {
        case complete
        case current
        case upcoming
    }

    private var requiredTutorialSteps: [TutorialBoardStep] {
        TutorialBoardStep.requiredSteps
    }

    private var openBoardShortcutTokens: [String] {
        viewModel.isDenMode ? ["n", "/", "Space"] : ["⌘", "T"]
    }

    private func stepState(_ step: TutorialBoardStep) -> StepState {
        let completedSteps = board.tutorialCompletedSteps ?? []
        if completedSteps.contains(step) { return .complete }
        if step.isRequired,
            requiredTutorialSteps.first(where: { !completedSteps.contains($0) }) == step
        {
            return .current
        }
        if !step.isRequired, requiredTutorialSteps.allSatisfy({ completedSteps.contains($0) }) {
            return .current
        }
        return .upcoming
    }

    private func shortcutHint(_ title: String, tokens: [String]) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ShortcutChip(tokens: tokens, width: nil)
        }
        .padding(.top, 3)
    }

    private func stepStatus(_ step: TutorialBoardStep) -> some View {
        let isComplete = stepState(step) == .complete
        return Image(systemSymbol: isComplete ? .checkmarkCircleFill : .circle)
            .font(.title3)
            .foregroundStyle(
                isComplete
                    ? (differentiateWithoutColor ? Color.primary : profileColor)
                    : Color.secondary
            )
            .frame(width: 28, height: 28)
            .accessibilityLabel(isComplete ? "Completed" : "Not completed")
    }
}
