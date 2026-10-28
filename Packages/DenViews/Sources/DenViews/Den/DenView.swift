public import DenDomain
public import DenModels
import SFSafeSymbols
public import SwiftUI

public struct DenView<Header: View, Rail: View, Strip: View, Panels: View, Drawer: View>: View {
    private let profileName: String?
    private let profileColor: Color
    private let isPrivateDen: Bool
    private let shouldShowHeader: Bool
    private let header: Header

    private let motionPreference: MotionPreference
    private let drawerStyle: DrawerStyle
    private let sheetScale: Int
    private let activities: [DownloadActivity]
    private let onScaleChange: (Int) -> Void
    private let onMotionChange: (Bool) -> Void
    private let onOpenTutorial: (Double) -> Void
    private let rail: Rail
    private let strip: (CGSize) -> Strip
    private let panels: (CGSize) -> Panels
    private let drawer: (CGSize) -> Drawer

    @Environment(DenWindowModel.self) private var windowModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    public init(
        profileName: String? = nil, profileColor: Color = .blue, isPrivateDen: Bool = false, shouldShowHeader: Bool,
        motionPreference: MotionPreference, drawerStyle: DrawerStyle, sheetScale: Int, activities: [DownloadActivity],
        onScaleChange: @escaping (Int) -> Void, onMotionChange: @escaping (Bool) -> Void,
        onOpenTutorial: @escaping (Double) -> Void,
        @ViewBuilder header: () -> Header, @ViewBuilder rail: () -> Rail,
        @ViewBuilder strip: @escaping (CGSize) -> Strip, @ViewBuilder panels: @escaping (CGSize) -> Panels,
        @ViewBuilder drawer: @escaping (CGSize) -> Drawer
    ) {
        self.profileName = profileName
        self.profileColor = profileColor
        self.isPrivateDen = isPrivateDen
        self.shouldShowHeader = shouldShowHeader
        self.motionPreference = motionPreference
        self.drawerStyle = drawerStyle
        self.sheetScale = sheetScale
        self.activities = activities
        self.onScaleChange = onScaleChange
        self.onMotionChange = onMotionChange
        self.onOpenTutorial = onOpenTutorial
        self.header = header()
        self.rail = rail()
        self.strip = strip
        self.panels = panels
        self.drawer = drawer
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // Keep the switcher and Strip in one native detail column so opening the Rail moves them together.
                NavigationSplitView(columnVisibility: boardRailVisibility) {
                    rail
                        .navigationSplitViewColumnWidth(min: 192, ideal: 208, max: 224)
                        .accessibilityHidden(windowModel.temporaryContext != nil)
                } detail: {
                    VStack(spacing: 0) {
                        if shouldShowHeader {
                            header
                                .frame(maxWidth: .infinity)
                                .frame(height: DenLayout.denHeaderHeight)
                                .accessibilityHidden(windowModel.temporaryContext != nil)
                        }

                        GeometryReader { detailGeometry in
                            denContent(in: detailGeometry.size)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(.container, edges: windowModel.isZenViewPresented ? .top : [])
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(
                    DenMotion.spatial(reduceMotion: shouldReduceMotion),
                    value: windowModel.isBoardRailPresented
                )

                panels(geometry.size)

                DenNotificationOverlay(
                    profileColor: profileColor,
                    shouldShowHeader: shouldShowHeader
                )
                drawer(geometry.size)
                DenFeedbackOverlay(
                    profileColor: profileColor,
                    shouldReduceMotion: shouldReduceMotion,
                    activities: activities
                )
                .zIndex(DenOverlayLayer.toast)
            }
            .onChange(of: sheetScale) { _, scale in
                onScaleChange(scale)
            }
            .onAppear {
                onMotionChange(shouldReduceMotion)
            }
            .onChange(of: shouldReduceMotion) { _, reduceMotion in
                onMotionChange(reduceMotion)
            }
            .animation(DenMotion.feedback(reduceMotion: shouldReduceMotion), value: windowModel.temporaryContext)
            .animation(DenMotion.feedback(reduceMotion: shouldReduceMotion), value: deskFilter.isPresented)
            .animation(DenMotion.spatial(reduceMotion: shouldReduceMotion), value: windowModel.isZenViewPresented)
            .animation(DenMotion.spatial(reduceMotion: shouldReduceMotion), value: windowModel.isDrawerOpen)
            .animation(DenMotion.spatial(reduceMotion: shouldReduceMotion), value: drawerStyle)
        }
        .environment(windowModel.boardEditing)
        .environment(windowModel.desks)
        .environment(windowModel.overview)
        .environment(windowModel.drawer)
        .environment(windowModel.openBoard)
        .environment(windowModel.deskFilter)
        .environment(windowModel.notificationList)
        .background(
            DenBackground(
                isDenMode: windowModel.isDenMode,
                isPrivateDen: isPrivateDen,
                profileColor: profileColor)
        )
        .frame(
            minWidth: DenLayout.minimumWindowWidth,
            minHeight: DenLayout.minimumWindowHeight
        )
        .navigationTitle(titlebarTitle)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("den-content")
        .accessibilityLabel(contentAccessibilityValue)
        .accessibilityValue(contentAccessibilityValue)
        .transaction(value: windowModel.boardMutationAnimationSuppressionRequest) { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private var boardRailVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: {
                windowModel.isBoardRailPresented && !windowModel.isZenViewPresented
                    ? .doubleColumn
                    : .detailOnly
            },
            set: { visibility in
                guard !windowModel.isZenViewPresented else { return }
                windowModel.setBoardRailPresented(visibility != .detailOnly)
            }
        )
    }

    private var deskFilter: DeskFilterModel { windowModel.deskFilter }

    @ViewBuilder
    private func denContent(in size: CGSize) -> some View {
        ZStack(alignment: .top) {
            strip(size)
                .allowsHitTesting(
                    windowModel.temporaryContext == nil && windowModel.desks.focusedDesk?.boards.isEmpty == false
                )
                .accessibilityHidden(
                    windowModel.temporaryContext != nil || windowModel.desks.focusedDesk?.boards.isEmpty != false
                )

            if windowModel.desks.focusedDesk?.boards.isEmpty != false {
                EmptyDenView(
                    openBoard: { windowModel.showOpenBoardPanel() },
                    openTutorial: {
                        onOpenTutorial(newBoardWidth(in: size))
                    },
                    showKeyboardShortcuts: windowModel.showKeyboardShortcuts
                )
                .allowsHitTesting(windowModel.temporaryContext == nil)
                .accessibilityHidden(windowModel.temporaryContext != nil)
            }

            if deskFilter.isPresented && deskFilter.filteredBoards.isEmpty {
                ContentUnavailableView.search(text: deskFilter.query)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }

            if deskFilter.isPresented {
                DeskFilterOverlay(profileColor: profileColor)
                    .zIndex(DenOverlayLayer.deskFilter)
            }

            BoardStripIndicator(profileColor: profileColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            windowModel.updateBoardLayout(
                availableWidth: size.width - DenLayout.outerInset * 2,
                spacing: DenLayout.outerInset
            )
        }
        .onChange(of: size.width) { _, width in
            windowModel.updateBoardLayout(
                availableWidth: width - DenLayout.outerInset * 2,
                spacing: DenLayout.outerInset
            )
        }
    }

    private var contentAccessibilityValue: String {
        let inputContext = windowModel.isDenMode ? "Den Mode" : "Sheet Input"
        return windowModel.isFocusModePresented ? "\(inputContext), Focus Mode" : inputContext
    }

    private var titlebarTitle: String {
        let profileTitle = profileName ?? "Den"
        guard windowModel.temporaryContext == nil, windowModel.boardEditing.focusedBoard != nil else {
            return profileTitle
        }
        return "\(profileTitle) · \(windowModel.isDenMode ? "DEN MODE" : "SHEET INPUT")"
    }

    private func newBoardWidth(in size: CGSize) -> Double {
        DenLayout.newBoardWidth(in: size, focusedBoardWidth: windowModel.boardEditing.focusedBoard?.width)
    }

    private var shouldReduceMotion: Bool {
        DenMotion.shouldReduceMotion(
            preference: motionPreference,
            systemReduceMotion: systemReduceMotion
        )
    }
}
