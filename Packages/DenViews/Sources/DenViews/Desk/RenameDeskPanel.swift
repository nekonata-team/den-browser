import DenDomain
import DenPresentationModels
import SFSafeSymbols
import SwiftUI

public struct RenameDeskPanel: View {
    @Environment(DeskListModel.self) private var desks
    @Environment(DenWindowModel.self) private var windowModel
    @State private var text = ""
    @FocusState private var isFocused: Bool

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: DenPanelLayout.contentSpacing) {
            DenPanelHeader(systemSymbol: .pencil) {
                TextField(
                    text: $text,
                    prompt: Text("Desk label")
                ) {
                    Text("Rename desk")
                }
                .denPanelHeaderField()
                .focused($isFocused)
                .onSubmit {
                    TextInputComposition.performUnlessActive {
                        desks.renameFocusedDesk(to: text)
                    }
                }
            }
            DenPanelHint("Press Return to confirm, Escape to cancel")
        }
        .denPanel()
        .onAppear {
            text = desks.focusedDesk?.label ?? ""
            DispatchQueue.main.async { isFocused = true }
        }
        .onExitCommand { windowModel.hideRenameDeskPanel() }
    }
}
