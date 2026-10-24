import DenDomain
import DenModels
import Foundation
import SFSafeSymbols
import SwiftUI

public struct DeskSwitcher: View {
    @Environment(DeskListModel.self) private var desks
    @Environment(DenWindowModel.self) private var windowModel
    @Environment(AppearanceModel.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.appearsActive) private var appearsActive

    let profileColor: Color
    let canOpenInNewWindow: (DeskID) -> Bool
    let isPresentedInAnotherWindow: (DeskID) -> Bool
    let onOpenInNewWindow: (DeskID) -> Void
    @State private var scrollPosition = ScrollPosition(idType: DeskID.self)
    @State private var frames: [DeskID: CGRect] = [:]
    @State private var drag: DeskDragState?
    @State private var lastAutoScrollTime = 0.0

    private var shouldReduceMotion: Bool {
        DenMotion.shouldReduceMotion(
            preference: preferences.motionPreference,
            systemReduceMotion: systemReduceMotion
        )
    }

    public init(
        profileColor: Color, canOpenInNewWindow: @escaping (DeskID) -> Bool,
        isPresentedInAnotherWindow: @escaping (DeskID) -> Bool, onOpenInNewWindow: @escaping (DeskID) -> Void
    ) {
        self.profileColor = profileColor
        self.canOpenInNewWindow = canOpenInNewWindow
        self.isPresentedInAnotherWindow = isPresentedInAnotherWindow
        self.onOpenInNewWindow = onOpenInNewWindow
    }

    public var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 4) {
                    HStack(spacing: 4) {
                        ForEach(Array(desks.desks.enumerated()), id: \.element.id) { index, desk in
                            deskSwitcherItem(desk, number: index + 1, in: geometry.size)
                        }

                        Button {
                            windowModel.showNewDeskPanel()
                        } label: {
                            Image(systemSymbol: .plus)
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .tint(.secondary)
                        .fixedSize()
                        .disabled(!desks.canCreateDesk)
                        .accessibilityLabel("New Desk")
                        .help("New Desk")
                    }
                    .frame(height: DenLayout.deskSwitcherHeight)
                    .scrollTargetLayout()
                }
                .padding(.horizontal, DenLayout.chromeHorizontalPadding)
                .animation(
                    DenMotion.spatial(reduceMotion: shouldReduceMotion),
                    value: desks.desks.map(\.id)
                )
            }
            .defaultScrollAnchor(preferences.deskSwitcherAlignment == .center ? .center : .leading, for: .alignment)
            .scrollPosition($scrollPosition, anchor: .center)
            .coordinateSpace(name: DeskSwitcherCoordinateSpace.name)
            .scrollIndicators(.never)
            .onChange(of: desks.presentedDeskID) { _, deskID in
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
        .onChange(of: windowModel.deskDragCancellationRequest) { _, _ in cancelDeskDrag() }
        .onChange(of: windowModel.temporaryContext) { _, context in
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
                Image(systemSymbol: .macwindow)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Open in another window")
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: DenLayout.deskButtonMaxWidth)
        .padding(.horizontal, 8)
        .frame(height: DenLayout.deskButtonHeight)
        .background {
            if desk.id == desks.presentedDeskID {
                Capsule().fill(profileColor.opacity(0.35))
            }
        }
        .overlay {
            if desk.id == desks.presentedDeskID, differentiateWithoutColor {
                Capsule().stroke(Color.primary, lineWidth: 1)
            }
        }
        .glassEffect(.regular, in: Capsule())
        .contentShape(.capsule)
        .contextMenu {
            Button {
                onOpenInNewWindow(desk.id)
            } label: {
                Label("Open Desk in New Window", systemSymbol: .macwindowBadgePlus)
            }
            .disabled(!canOpenInNewWindow(desk.id))

            Button {
                desks.copyDeskID(desk.id)
            } label: {
                Label("Copy Desk ID", systemSymbol: .documentOnDocument)
            }

            Divider()

            Button {
                desks.focusDesk(desk.id)
                windowModel.showRenameDeskPanel()
            } label: {
                Label("Rename Desk", systemSymbol: .pencil)
            }
            .disabled(!desks.canSelectDesk(desk.id))

            Button {
                desks.duplicateDesk(desk.id)
            } label: {
                Label("Duplicate Desk", systemSymbol: .plusSquareOnSquare)
            }
            .disabled(!desks.canCreateDesk)

            Button(role: .destructive) {
                desks.focusDesk(desk.id)
                desks.deleteFocusedDesk()
            } label: {
                Label("Delete Desk", systemSymbol: .trash)
            }
            .disabled(!desks.canSelectDesk(desk.id) || !desks.canDeleteFocusedDesk)

            Divider()

            Button {
                desks.focusDesk(desk.id)
                windowModel.showSaveDeskPresetPanel()
            } label: {
                Label("Save Desk as Preset...", systemSymbol: .squareAndArrowDown)
            }
            .disabled(!desks.canSelectDesk(desk.id))

            Menu("Export") {
                Button {
                    desks.exportDeskLinks(for: desk.id)
                } label: {
                    Label("Save Desk Links as Markdown...", systemSymbol: .arrowDownDocument)
                }
                .disabled(!desks.canExportDeskLinks(for: desk.id))

                Button {
                    desks.copyDeskLinks(for: desk.id)
                } label: {
                    Label("Copy Desk Links as Markdown", systemSymbol: .documentOnDocument)
                }
                .disabled(!desks.canExportDeskLinks(for: desk.id))
            }

            Button {
                desks.focusDesk(desk.id)
                windowModel.showReplaceDeskPanel()
            } label: {
                Label("Replace Desk...", systemSymbol: .rectangleStackBadgeMinus)
            }
            .disabled(!desks.canSelectDesk(desk.id))

            Button {
                windowModel.showDeskPresetManagement()
            } label: {
                Label("Manage Presets...", systemSymbol: .sliderHorizontal3)
            }

            Divider()

            Button {
                windowModel.showNewDeskPanel()
            } label: {
                Label("New Desk...", systemSymbol: .plus)
            }
            .disabled(!desks.canCreateDesk)
        }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(DeskSwitcherCoordinateSpace.name))
                .onChanged { updateDeskDrag(desk, value: $0, in: size) }
                .onEnded { finishDeskGesture(desk, value: $0, in: size) }
        )
        .allowsHitTesting(!windowModel.isDeskDragging || drag?.deskID == desk.id)
        .help("Drag to reorder Desk")
        .accessibilityHint("Drag to reorder this Desk")
        .accessibilityLabel(
            "\(number). \(desk.label)"
                + (isPresentedElsewhere ? ", open in another window" : "")
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(desk.id == desks.presentedDeskID ? .isSelected : [])
        .accessibilityValue(desk.id == desks.presentedDeskID ? "Presented Desk" : "")
        .accessibilityAction { desks.focusDesk(desk.id) }
        .accessibilityAction(named: "Move Desk Left") {
            desks.moveDesk(desk.id, by: -1)
        }
        .accessibilityAction(named: "Move Desk Right") {
            desks.moveDesk(desk.id, by: 1)
        }
        .accessibilityIdentifier("desk-switcher.\(desk.id.rawValue.uuidString.lowercased())")
        .id(desk.id)
    }

    private func deskFrameBackground(for deskID: DeskID) -> some View {
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
                let frame = frames[desk.id], desks.beginDeskDrag(desk.id)
            else { return }
            drag = DeskDragState(
                deskID: desk.id,
                originalOrder: desks.desks.map(\.id),
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
            desks.focusDesk(desk.id)
        }
    }

    private func updateDeskInsertion() {
        guard var current = drag else { return }
        while let index = desks.desks.firstIndex(where: { $0.id == current.deskID }),
            let targetIndex = HorizontalDragInsertion.targetIndex(
                draggedID: current.deskID,
                orderedIDs: desks.desks.map(\.id),
                desiredCenterX: current.desiredCenterX,
                frames: frames)
        {
            let crossedDesk = desks.desks[targetIndex]
            desks.previewDeskMove(current.deskID, to: DeskIndex(rawValue: targetIndex))
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
                orderedIDs: desks.desks.map(\.id),
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
            desks.finishDeskDrag()
            drag = nil
        } else {
            cancelDeskDrag()
        }
    }

    private func cancelDeskDrag() {
        guard let current = drag else { return }
        let restore = {
            desks.restoreDeskOrder(current.originalOrder)
            desks.finishDeskDrag()
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
    let deskID: DeskID
    let originalOrder: [DeskID]
    let startCenterX: CGFloat
    var translation: CGSize = .zero
    var offset: CGFloat = 0

    var desiredCenterX: CGFloat {
        startCenterX + translation.width
    }
}

private struct DeskFramePreferenceKey: PreferenceKey {
    static let defaultValue: [DeskID: CGRect] = [:]

    static func reduce(value: inout [DeskID: CGRect], nextValue: () -> [DeskID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
