import SFSafeSymbols
import SwiftUI

struct ZmxSessionsPanel: View {
    let profileColor: Color

    @Environment(DenStore.self) private var store
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DenPanelLayout.contentSpacing) {
            header
            searchField

            if model.isLoading && model.groups.isEmpty {
                ProgressView("Loading zmx Sessions…")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DenPanelLayout.contentSpacing)
            } else if let message = model.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if model.groups.isEmpty {
                ContentUnavailableView("No zmx Sessions", systemSymbol: .appleTerminal)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DenPanelLayout.contentSpacing)
            } else if model.filteredGroups.isEmpty {
                ContentUnavailableView.search(text: model.query)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DenPanelLayout.contentSpacing)
            } else {
                sessionList
            }

            footer
        }
        .denPanel(width: 520)
        .confirmationDialog(
            pendingDeletionTitle,
            isPresented: Binding(
                get: { !model.pendingDeletion.isEmpty },
                set: { if !$0 { model.clearPendingDeletion() } })
        ) {
            Button(role: .destructive) {
                let targets = model.pendingDeletion
                store.killZmxSessions(targets)
            } label: {
                Label(pendingDeletionActionLabel, systemSymbol: .xmarkCircle)
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { model.clearPendingDeletion() }
        } message: {
            Text(pendingDeletionMessage)
        }
        .onExitCommand { store.hideZmxSessions() }
        .onChange(of: model.isFilterInputActive) { _, isActive in
            isSearchFocused = isActive
        }
    }

    private var model: ZmxSessionsModel { store.zmxSessions }

    private var header: some View {
        HStack(spacing: DenPanelLayout.controlSpacing) {
            DenPanelHeader(icon: ZmxIcon(size: 18)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("zmx Sessions")
                        .font(.headline)
                    Text("\(model.activeSessionCount) active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.hasMarkedSessions {
                Button("End \(model.markedSessionCount)") {
                    store.requestZmxSessionDeletion()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .help("End selected Sessions")
            }
            Button(action: store.refreshZmxSessions) {
                Label("Refresh", systemSymbol: .arrowClockwise)
                    .labelStyle(.iconOnly)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Refresh zmx Sessions")
            .accessibilityLabel("Refresh zmx Sessions")
            DenCloseButton(label: "Close zmx Sessions") { store.hideZmxSessions() }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemSymbol: .magnifyingglass)
                .foregroundStyle(model.isFilterInputActive ? .primary : .secondary)
                .accessibilityHidden(true)
            TextField(
                text: Binding(
                    get: { model.query },
                    set: { model.setQuery($0) }
                ),
                prompt: Text("Filter zmx Sessions")
            ) {
                Text("Filter zmx Sessions")
            }
            .labelsHidden()
            .textFieldStyle(.plain)
            .focused($isSearchFocused)
            .disabled(!model.isFilterInputActive)
            Spacer(minLength: 0)
            Text("/")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Color.primary.opacity(model.isFilterInputActive ? 0.08 : 0.04),
            in: RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
        )
        .onTapGesture { store.enterZmxSessionFilter() }
    }

    private var sessionList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DenPanelLayout.controlSpacing) {
                    ForEach(model.filteredGroups) { group in
                        if group.isRootActive {
                            sessionRow(
                                group.rootSessionName,
                                detail: model.processName(for: group.rootSessionName),
                                isChild: false
                            )
                            .id(group.rootSessionName)
                        } else {
                            missingRootRow(group.rootSessionName)
                        }
                        ForEach(group.childSessionNames, id: \.self) { sessionName in
                            sessionRow(
                                sessionName,
                                detail: model.processName(for: sessionName),
                                isChild: true
                            )
                            .id(sessionName)
                        }
                    }
                }
            }
            .onAppear {
                scrollToSelected(using: proxy)
            }
            .onChange(of: model.selectedSessionName) { _, _ in
                scrollToSelected(using: proxy)
            }
        }
        .frame(maxHeight: 420)
    }

    private func missingRootRow(_ sessionName: String) -> some View {
        HStack(spacing: DenPanelLayout.controlSpacing) {
            Image(systemSymbol: .exclamationmarkTriangle)
                .foregroundStyle(.secondary)
            Text("Missing root")
                .font(.caption.weight(.medium))
            Text(sessionName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 28)
        .accessibilityLabel("Missing root \(sessionName)")
    }

    private func sessionRow(
        _ sessionName: String,
        detail: String?,
        isChild: Bool
    ) -> some View {
        let isFocused = model.selectedSessionName == sessionName
        let isMarked = model.isMarked(sessionName)
        let focusColor = differentiateWithoutColor ? Color.primary : profileColor

        return HStack(spacing: DenPanelLayout.controlSpacing) {
            Button {
                model.toggleMarking(sessionName)
            } label: {
                Image(systemSymbol: isMarked ? .checkmarkCircleFill : .circle)
                    .imageScale(.medium)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isMarked ? focusColor : .secondary)
            .help(isMarked ? "Deselect \(sessionName)" : "Select \(sessionName)")
            .accessibilityLabel(isMarked ? "Deselect \(sessionName)" : "Select \(sessionName)")

            if isChild {
                Image(systemSymbol: .arrowTurnDownRight)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(sessionName)
                    .font(.body.weight(isFocused ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 5) {
                    Text(detail ?? "Unknown process")
                    Text("·")
                    if let location = store.zmxBoardLocation(for: sessionName) {
                        Text("Attached · \(location)")
                    } else {
                        Text("Not attached")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            Button {
                store.openZmxSession(sessionName)
            } label: {
                Label("Open", systemSymbol: .arrowUpRightSquare)
                    .labelStyle(.iconOnly)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Open \(sessionName)")
            .accessibilityLabel("Open \(sessionName)")

            Button(role: .destructive) {
                store.requestZmxSessionDeletion(sessionName)
            } label: {
                Label("End", systemSymbol: .xmarkCircle)
                    .labelStyle(.iconOnly)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("End \(sessionName)")
            .accessibilityLabel("End \(sessionName)")
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 48)
        .background(
            Color.primary.opacity(isMarked ? 0.1 : 0.04),
            in: RoundedRectangle(cornerRadius: DenRadius.small)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DenRadius.small)
                .stroke(isFocused ? focusColor : .clear, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: DenRadius.small))
        .onTapGesture { model.select(sessionName: sessionName) }
        .accessibilityAddTraits(isFocused ? .isSelected : [])
        .accessibilityHint("Return opens this Session. Space selects it.")
    }

    private var footer: some View {
        Text(
            "↑↓ / j k Focus  ·  Space Select  ·  Return Open  ·  x End\n⌘A Select visible  ·  r Refresh  ·  / Filter  ·  Esc Clear / Close"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var pendingDeletionTitle: String {
        if let sessionName = model.pendingDeletion.first, model.pendingDeletion.count == 1 {
            return "End \(sessionName)?"
        }
        return "End \(model.pendingDeletion.count) zmx Sessions?"
    }

    private var pendingDeletionActionLabel: String {
        model.pendingDeletion.count == 1 ? "End Session" : "End Sessions"
    }

    private var pendingDeletionMessage: String {
        let attachedCount = model.pendingDeletion.compactMap(store.zmxBoardLocation(for:)).count
        let boardMessage =
            attachedCount == 0
            ? "No attached Boards are affected."
            : "\(attachedCount) attached Board\(attachedCount == 1 ? "" : "s") close and can be restored from Recently Removed Boards."
        return
            "This ends only the selected Session\(model.pendingDeletion.count == 1 ? "" : "s"). \(boardMessage) Child Sessions remain running unless selected."
    }

    private func scrollToSelected(using proxy: ScrollViewProxy) {
        guard let selectedName = model.selectedSessionName else { return }
        proxy.scrollTo(selectedName, anchor: .center)
    }
}
