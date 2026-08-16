import Foundation
import SwiftUI

struct DeskSwitcher: View {
    @Environment(DenStore.self) private var store
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appearsActive) private var appearsActive

    let profileColor: Color
    let canOpenInNewWindow: (UUID) -> Bool
    let isPresentedInAnotherWindow: (UUID) -> Bool
    let onOpenInNewWindow: (UUID) -> Void
    @State private var scrollPosition = ScrollPosition(idType: UUID.self)
    @State private var frames: [UUID: CGRect] = [:]
    @State private var drag: DeskDragState?
    @State private var lastAutoScrollTime = 0.0

    private var shouldReduceMotion: Bool {
        DenMotion.shouldReduceMotion(
            preference: preferences.motionPreference,
            systemReduceMotion: systemReduceMotion
        )
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: DenLayout.outerInset) {
                    HStack(spacing: DenLayout.outerInset) {
                        ForEach(Array(store.state.desks.enumerated()), id: \.element.id) { index, desk in
                            deskSwitcherItem(desk, number: index + 1, in: geometry.size)
                        }
                    }
                    .frame(height: DenLayout.deskSwitcherHeight)
                    .scrollTargetLayout()
                }
                .padding(.horizontal, DenLayout.chromeHorizontalPadding)
                .animation(
                    DenMotion.spatial(reduceMotion: shouldReduceMotion),
                    value: store.state.desks.map(\.id)
                )
            }
            .scrollPosition($scrollPosition, anchor: .center)
            .coordinateSpace(name: DeskSwitcherCoordinateSpace.name)
            .scrollIndicators(.never)
            .onChange(of: store.presentedDeskID) { _, deskID in
                cancelDeskDrag()
                withAnimation(DenMotion.spatial(reduceMotion: shouldReduceMotion)) {
                    scrollPosition.scrollTo(id: deskID, anchor: .center)
                }
            }
            .onPreferenceChange(DeskFramePreferenceKey.self) {
                frames = $0
                alignDraggedDesk()
            }
        }
        .frame(height: DenLayout.deskSwitcherHeight)
        .onChange(of: store.deskDragCancellationRequest) { _, _ in cancelDeskDrag() }
        .onChange(of: store.temporaryContext) { _, context in
            if context != nil { cancelDeskDrag() }
        }
        .onChange(of: appearsActive) { _, isActive in
            if !isActive { cancelDeskDrag() }
        }
    }

    private func deskSwitcherItem(_ desk: DeskState, number: Int, in size: CGSize) -> some View {
        let isDragged = drag?.deskID == desk.id
        return deskButton(desk, number: number, in: size)
            .offset(x: isDragged ? drag?.offset ?? 0 : 0)
            .background(deskFrameBackground(for: desk.id))
            .zIndex(isDragged ? 2 : 1)
    }

    private func deskButton(_ desk: DeskState, number: Int, in size: CGSize) -> some View {
        let isPresentedElsewhere = isPresentedInAnotherWindow(desk.id)
        return HStack(spacing: 6) {
            Text("\(number). \(desk.label)")
                .lineLimit(1)

            if isPresentedElsewhere {
                Image(systemName: "macwindow")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Open in another window")
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: DenLayout.deskButtonMaxWidth)
        .padding(.horizontal, DenLayout.chromeHorizontalPadding)
        .frame(height: DenLayout.deskButtonHeight)
        .background {
            if desk.id == store.presentedDeskID {
                Capsule().fill(profileColor.opacity(0.35))
            }
        }
        .glassEffect(.regular, in: Capsule())
        .contentShape(.capsule)
        .contextMenu {
            Button {
                onOpenInNewWindow(desk.id)
            } label: {
                Label("Open Desk in New Window", systemImage: "macwindow.badge.plus")
            }
            .disabled(!canOpenInNewWindow(desk.id))

            Divider()

            Button {
                store.focusDesk(desk.id)
                store.showRenameDeskPanel()
            } label: {
                Label("Rename Desk", systemImage: "pencil")
            }
            .disabled(!store.canSelectDesk(desk.id))

            Button(role: .destructive) {
                store.focusDesk(desk.id)
                store.deleteFocusedDesk()
            } label: {
                Label("Delete Desk", systemImage: "trash")
            }
            .disabled(!store.canSelectDesk(desk.id) || !store.canDeleteFocusedDesk)

            Divider()

            Button {
                store.focusDesk(desk.id)
                store.showSaveDeskPresetPanel()
            } label: {
                Label("Save Desk as Preset...", systemImage: "square.and.arrow.down")
            }
            .disabled(!store.canSelectDesk(desk.id) || desk.boards.isEmpty)

            Menu("Export") {
                Button {
                    store.exportDeskLinks(for: desk.id)
                } label: {
                    Label("Save Desk Links as Markdown...", systemImage: "arrow.down.doc")
                }
                .disabled(!store.canExportDeskLinks(for: desk.id))

                Button {
                    store.copyDeskLinks(for: desk.id)
                } label: {
                    Label("Copy Desk Links as Markdown", systemImage: "doc.on.doc")
                }
                .disabled(!store.canExportDeskLinks(for: desk.id))

                Divider()

                Button {
                    store.focusDesk(desk.id)
                    store.captureFocusedDeskScreenshot()
                } label: {
                    Label("Capture Desk Screenshot...", systemImage: "camera.on.rectangle")
                }
                .disabled(!store.canSelectDesk(desk.id) || desk.boards.isEmpty)
            }

            Button {
                store.focusDesk(desk.id)
                store.showReplaceDeskPanel()
            } label: {
                Label("Replace Desk...", systemImage: "rectangle.stack.badge.minus")
            }
            .disabled(!store.canSelectDesk(desk.id))

            Button {
                store.showDeskPresetManagement()
            } label: {
                Label("Manage Presets...", systemImage: "slider.horizontal.3")
            }

            Divider()

            Button {
                store.showNewDeskPanel()
            } label: {
                Label("New Desk...", systemImage: "plus")
            }
            .disabled(!store.canCreateDesk)
        }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(DeskSwitcherCoordinateSpace.name))
                .onChanged { updateDeskDrag(desk, value: $0, in: size) }
                .onEnded { finishDeskGesture(desk, value: $0, in: size) }
        )
        .allowsHitTesting(!store.isDeskDragging || drag?.deskID == desk.id)
        .help("Drag to reorder Desk")
        .accessibilityHint("Drag to reorder this Desk")
        .accessibilityLabel(
            "\(number). \(desk.label)"
                + (isPresentedElsewhere ? ", open in another window" : "")
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(desk.id == store.presentedDeskID ? .isSelected : [])
        .accessibilityValue(desk.id == store.presentedDeskID ? "Presented Desk" : "")
        .accessibilityAction { store.focusDesk(desk.id) }
        .accessibilityAction(named: "Move Desk Left") {
            store.moveDesk(desk.id, by: -1)
        }
        .accessibilityAction(named: "Move Desk Right") {
            store.moveDesk(desk.id, by: 1)
        }
        .accessibilityIdentifier("desk-switcher.\(desk.id.uuidString.lowercased())")
        .id(desk.id)
    }

    private func deskFrameBackground(for deskID: UUID) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: DeskFramePreferenceKey.self,
                value: [deskID: proxy.frame(in: .named(DeskSwitcherCoordinateSpace.name))]
            )
        }
    }

    private func updateDeskDrag(_ desk: DeskState, value: DragGesture.Value, in size: CGSize) {
        if drag == nil {
            guard hypot(value.translation.width, value.translation.height) >= 4,
                let frame = frames[desk.id], store.beginDeskDrag(desk.id)
            else { return }
            drag = DeskDragState(
                deskID: desk.id,
                originalOrder: store.state.desks.map(\.id),
                startCenterX: frame.midX
            )
        }

        guard var current = drag, current.deskID == desk.id else { return }
        current.translation = value.translation
        if let frame = frames[desk.id] {
            current.offset = current.desiredCenterX - frame.midX
        }
        drag = current
        updateDeskInsertion()
        autoScroll(at: value.location, in: size)
    }

    private func finishDeskGesture(_ desk: DeskState, value: DragGesture.Value, in size: CGSize) {
        if drag?.deskID == desk.id {
            finishDeskDrag(value: value, in: size)
        } else if hypot(value.translation.width, value.translation.height) < 4 {
            store.focusDesk(desk.id)
        }
    }

    private func updateDeskInsertion() {
        guard var current = drag else { return }
        while let index = store.state.desks.firstIndex(where: { $0.id == current.deskID }),
            let targetIndex = HorizontalDragInsertion.targetIndex(
                draggedID: current.deskID,
                orderedIDs: store.state.desks.map(\.id),
                desiredCenterX: current.desiredCenterX,
                frames: frames)
        {
            let crossedDesk = store.state.desks[targetIndex]
            store.previewDeskMove(current.deskID, to: targetIndex)
            let direction = targetIndex > index ? -1.0 : 1.0
            current.offset += direction * ((frames[crossedDesk.id]?.width ?? 0) + 8)
            drag = current
        }
    }

    private func alignDraggedDesk() {
        guard var current = drag, let frame = frames[current.deskID] else { return }
        let offset = current.desiredCenterX - frame.midX
        guard abs(offset - current.offset) > 0.5 else { return }
        current.offset = offset
        drag = current
    }

    private func autoScroll(at location: CGPoint, in size: CGSize) {
        guard let current = drag else { return }
        guard
            let decision = HorizontalDragAutoScroll.decision(
                location: location,
                size: size,
                draggedID: current.deskID,
                orderedIDs: store.state.desks.map(\.id),
                edge: 40
            )
        else { return }

        let now = Date.timeIntervalSinceReferenceDate
        guard now - lastAutoScrollTime >= decision.interval else { return }
        lastAutoScrollTime = now
        withAnimation(.linear(duration: shouldReduceMotion ? 0 : 0.14)) {
            scrollPosition.scrollTo(id: decision.targetID, anchor: .center)
        }
    }

    private func finishDeskDrag(value: DragGesture.Value, in size: CGSize) {
        guard drag != nil else { return }
        let isInside =
            value.location.x >= 0 && value.location.x <= size.width
            && value.location.y >= 0 && value.location.y <= size.height
        if isInside {
            store.finishDeskDrag()
            drag = nil
        } else {
            cancelDeskDrag()
        }
    }

    private func cancelDeskDrag() {
        guard let current = drag else { return }
        let restore = {
            store.restoreDeskOrder(current.originalOrder)
            store.finishDeskDrag()
            drag = nil
        }
        if shouldReduceMotion {
            restore()
        } else {
            withAnimation(DenMotion.spatial(reduceMotion: shouldReduceMotion)) {
                restore()
            }
        }
    }
}

private enum DeskSwitcherCoordinateSpace {
    static let name = "desk-switcher"
}

private struct DeskDragState {
    let deskID: UUID
    let originalOrder: [UUID]
    let startCenterX: CGFloat
    var translation: CGSize = .zero
    var offset: CGFloat = 0

    var desiredCenterX: CGFloat {
        startCenterX + translation.width
    }
}

struct DeskFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
