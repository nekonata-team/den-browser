import DenDomain
import DenPresentationModels
import SwiftUI

public struct DenActivePanelOverlay<Content: View>: View {
    private let size: CGSize
    private let shouldShowHeader: Bool
    private let motionPreference: MotionPreference
    private let restoreInput: () -> Void
    private let content: (TemporaryContext, CGFloat, CGFloat) -> Content
    @Environment(DenWindowModel.self) private var windowModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    public init(
        size: CGSize, shouldShowHeader: Bool, motionPreference: MotionPreference,
        restoreInput: @escaping () -> Void,
        @ViewBuilder content: @escaping (TemporaryContext, CGFloat, CGFloat) -> Content
    ) {
        self.size = size
        self.shouldShowHeader = shouldShowHeader
        self.motionPreference = motionPreference
        self.restoreInput = restoreInput
        self.content = content
    }

    public var body: some View {
        if let context = windowModel.temporaryContext, context != .drawer {
            dismissBlocker(onDismiss: dismissTemporaryPresentation)
                .frame(width: size.width, height: size.height)
                .zIndex(DenOverlayLayer.activePanel)
            panel(context)
                .zIndex(DenOverlayLayer.activePanel)
        }
    }

    @ViewBuilder
    private func panel(_ context: TemporaryContext) -> some View {
        let content = content(
            context, DenLayout.newBoardWidth(in: size, focusedBoardWidth: windowModel.navigation.focusedBoard?.width),
            DenLayout.boardHeight(for: size, shouldShowHeader: shouldShowHeader))
        switch context {
        case .overview, .boardActivity:
            content
                .padding(DenLayout.overlayInset)
                .transition(DenMotion.panelTransition(reduceMotion: shouldReduceMotion))
        case .keyboardShortcuts:
            panelOverlay(content.denPanel(width: DenPanelLayout.wideWidth))
        default:
            panelOverlay(content)
        }
    }

    private func panelOverlay<Panel: View>(_ content: Panel) -> some View {
        content
            .transition(DenMotion.panelTransition(reduceMotion: shouldReduceMotion))
            .padding(.top, 160)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func dismissTemporaryPresentation() {
        switch windowModel.temporaryContext {
        case .universalSearch:
            windowModel.hideUniversalSearch()
            restoreInput()
        case .essentialsPrefix:
            windowModel.exitEssentialsPrefix()
        case .openBoard:
            windowModel.hideOpenBoardPanel()
            restoreInput()
        case .zmxSessions:
            windowModel.hideZmxSessions()
        case .zmxDuplication:
            windowModel.hideZmxDuplicationPanel()
            restoreInput()
        case .editBoardLink:
            windowModel.hideEditBoardLinkPanel()
            restoreInput()
        case .newDesk, .replaceDesk:
            windowModel.hideNewDeskPanel()
        case .deskPresetManagement:
            windowModel.hideNewDeskPanel(exitsDenMode: true)
        case .overview:
            windowModel.hideOverview()
        case .boardActivity:
            windowModel.hideBoardActivity()
        case .keyboardShortcuts:
            windowModel.hideKeyboardShortcuts()
        case .boardWidth:
            windowModel.hideBoardWidthPanel()
        case .saveDeskPreset:
            windowModel.hideSaveDeskPresetPanel()
        case .renameBoard:
            windowModel.hideRenameBoardPanel()
        case .renameDesk:
            windowModel.hideRenameDeskPanel()
        case .drawer:
            windowModel.closeDrawer()
        case .saveEssential:
            windowModel.hideSaveEssentialPanel()
        case .profilePicker:
            windowModel.setTemporaryContext(nil)
        case nil:
            break
        }
    }

    private var shouldReduceMotion: Bool {
        DenMotion.shouldReduceMotion(preference: motionPreference, systemReduceMotion: systemReduceMotion)
    }
}
