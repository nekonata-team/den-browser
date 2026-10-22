import AppKit
import DenDomain
import DenPresentationModels
import SFSafeSymbols
public import SwiftUI

public struct SettingsView<Content: View>: View {
    private let content: (SettingsSection) -> Content
    private let onClose: () -> Void

    public init(onClose: @escaping () -> Void, @ViewBuilder content: @escaping (SettingsSection) -> Content) {
        self.onClose = onClose
        self.content = content
    }

    @State private var selection: SettingsSection? = .profiles

    public var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.title, systemSymbol: section.systemSymbol)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            content(selection ?? .profiles)
                .navigationTitle((selection ?? .profiles).title)
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 520, idealHeight: 560)
        .onDisappear {
            onClose()
        }
    }
}

public enum SettingsSection: String, CaseIterable, Identifiable {
    case profiles
    case appearance
    case shortcuts
    case essentials
    case terminal
    case web
    case features

    public var id: Self { self }

    var title: String {
        switch self {
        case .profiles:
            "Profiles"
        case .appearance:
            "Appearance"
        case .shortcuts:
            "Shortcuts"
        case .essentials:
            "Essentials"
        case .terminal:
            "Terminal"
        case .web:
            "Web"
        case .features:
            "Features"
        }
    }

    var systemSymbol: SFSymbol {
        switch self {
        case .profiles:
            .person2
        case .appearance:
            .circleLefthalfFilled
        case .shortcuts:
            .keyboard
        case .essentials:
            .sparkles
        case .terminal:
            .appleTerminal
        case .web:
            .globe
        case .features:
            .puzzlepiece
        }
    }
}
