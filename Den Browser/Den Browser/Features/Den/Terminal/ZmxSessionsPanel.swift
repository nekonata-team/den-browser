import SwiftUI

struct ZmxSessionsPanel: View {
    let profileColor: Color

    @Environment(DenStore.self) private var store
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DenPanelLayout.contentSpacing) {
            HStack {
                DenPanelHeader(systemImage: "arrow.triangle.2.circlepath") {
                    Text("zmx Sessions").font(.headline)
                }
                Spacer()
                Button(action: store.refreshZmxSessions) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Refresh zmx Sessions")
                .accessibilityLabel("Refresh zmx Sessions")
                DenCloseButton(label: "Close zmx Sessions") { store.hideZmxSessions() }
            }

            searchField

            if store.zmxSessionsIsLoading && store.zmxSessionGroups.isEmpty {
                ProgressView("Loading zmx Sessions…")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DenPanelLayout.contentSpacing)
            } else if let message = store.zmxSessionsMessage {
                Text(message).font(.caption).foregroundStyle(.red)
            } else if store.zmxSessionGroups.isEmpty {
                ContentUnavailableView("No zmx Sessions", systemImage: "terminal")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DenPanelLayout.contentSpacing)
            } else if store.filteredZmxSessionGroups.isEmpty {
                ContentUnavailableView.search(text: store.zmxSessionQuery)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DenPanelLayout.contentSpacing)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: DenPanelLayout.controlSpacing) {
                            ForEach(store.filteredZmxSessionGroups) { group in
                                sessionRow(
                                    group.rootSessionName,
                                    detail: group.isRootActive ? nil : "Missing root",
                                    isChild: false,
                                    isActionable: group.isRootActive
                                )
                                .id(group.rootSessionName)
                                ForEach(group.childSessionNames, id: \.self) { sessionName in
                                    sessionRow(
                                        sessionName,
                                        detail: nil,
                                        isChild: true,
                                        isActionable: true
                                    )
                                    .id(sessionName)
                                }
                            }
                        }
                    }
                    .onAppear {
                        scrollToSelected(using: proxy)
                    }
                    .onChange(of: store.zmxSessionSelectedName) { _, _ in
                        scrollToSelected(using: proxy)
                    }
                }
                .frame(maxHeight: 360)
            }

            Text("Open attaches a Session as a Board. Delete ends only that Session.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .denPanel(width: 460)
        .confirmationDialog(
            "Delete \(store.zmxSessionPendingDeletion ?? "zmx Session")?",
            isPresented: Binding(
                get: { store.zmxSessionPendingDeletion != nil },
                set: { if !$0 { store.zmxSessionPendingDeletion = nil } })
        ) {
            Button(role: .destructive) {
                if let pendingDeletion = store.zmxSessionPendingDeletion {
                    store.killZmxSession(pendingDeletion)
                }
            } label: {
                Label("Delete Session", systemImage: "trash")
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { store.zmxSessionPendingDeletion = nil }
        } message: {
            Text("This ends the Session and all its attached clients. Child Sessions remain running.")
        }
        .onExitCommand { store.hideZmxSessions() }
        .onChange(of: store.isZmxSessionFilterInputActive) { _, isActive in
            isSearchFocused = isActive
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(store.isZmxSessionFilterInputActive ? .primary : .secondary)
                .accessibilityHidden(true)
            TextField(
                text: Binding(
                    get: { store.zmxSessionQuery },
                    set: { store.setZmxSessionQuery($0) }
                ),
                prompt: Text("Filter zmx Sessions")
            ) {
                Text("Filter zmx Sessions")
            }
            .labelsHidden()
            .textFieldStyle(.plain)
            .focused($isSearchFocused)
            .disabled(!store.isZmxSessionFilterInputActive)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Color.primary.opacity(store.isZmxSessionFilterInputActive ? 0.08 : 0.04),
            in: RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
        )
        .onTapGesture { store.enterZmxSessionFilter() }
    }

    private func sessionRow(
        _ sessionName: String,
        detail: String?,
        isChild: Bool,
        isActionable: Bool
    ) -> some View {
        HStack(spacing: DenPanelLayout.controlSpacing) {
            if isChild {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(sessionName).lineLimit(1).truncationMode(.middle)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            if isActionable {
                Spacer()
                Button {
                    store.openZmxSession(sessionName)
                } label: {
                    Label("Open", systemImage: "arrow.up.right.square")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Open \(sessionName)")
                .accessibilityLabel("Open \(sessionName)")
                Button(role: .destructive) {
                    store.requestZmxSessionDeletion(sessionName)
                } label: {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Delete \(sessionName)")
                .accessibilityLabel("Delete \(sessionName)")
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 36)
        .background(
            isActionable && store.zmxSessionSelectedName == sessionName
                ? (differentiateWithoutColor ? Color.primary : profileColor.opacity(0.2))
                : Color.primary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: DenRadius.small)
        )
        .contentShape(RoundedRectangle(cornerRadius: DenRadius.small))
        .onTapGesture {
            if isActionable { store.zmxSessionSelectedName = sessionName }
        }
        .accessibilityAddTraits(
            isActionable && store.zmxSessionSelectedName == sessionName ? .isSelected : []
        )
        .accessibilityElement(children: .combine)
    }

    private func scrollToSelected(using proxy: ScrollViewProxy) {
        guard let selectedName = store.zmxSessionSelectedName else { return }
        proxy.scrollTo(selectedName, anchor: .center)
    }
}
