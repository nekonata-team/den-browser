import Foundation
import Observation

@MainActor
@Observable
public final class AppearanceModel {
    @ObservationIgnored private let readMotionPreference: () -> MotionPreference
    @ObservationIgnored private let readDeskSwitcherAlignment: () -> DeskSwitcherAlignment
    @ObservationIgnored private let readBoardCentering: () -> FocusedBoardCentering
    @ObservationIgnored private let readSheetScale: () -> Int
    @ObservationIgnored private let readDrawerStyle: () -> DrawerStyle
    @ObservationIgnored private let onSetMotionPreference: (MotionPreference) -> Void
    @ObservationIgnored private let onSetDeskSwitcherAlignment: (DeskSwitcherAlignment) -> Void
    @ObservationIgnored private let onSetBoardCentering: (FocusedBoardCentering) -> Void
    @ObservationIgnored private let onSetSheetScale: (Int) -> Void
    @ObservationIgnored private let onSetDrawerStyle: (DrawerStyle) -> Void

    public init(
        motionPreference: @escaping () -> MotionPreference,
        deskSwitcherAlignment: @escaping () -> DeskSwitcherAlignment,
        boardCentering: @escaping () -> FocusedBoardCentering,
        sheetScale: @escaping () -> Int,
        drawerStyle: @escaping () -> DrawerStyle,
        setMotionPreference: @escaping (MotionPreference) -> Void,
        setDeskSwitcherAlignment: @escaping (DeskSwitcherAlignment) -> Void,
        setBoardCentering: @escaping (FocusedBoardCentering) -> Void,
        setSheetScale: @escaping (Int) -> Void,
        setDrawerStyle: @escaping (DrawerStyle) -> Void
    ) {
        self.readMotionPreference = motionPreference
        self.readDeskSwitcherAlignment = deskSwitcherAlignment
        self.readBoardCentering = boardCentering
        self.readSheetScale = sheetScale
        self.readDrawerStyle = drawerStyle
        self.onSetMotionPreference = setMotionPreference
        self.onSetDeskSwitcherAlignment = setDeskSwitcherAlignment
        self.onSetBoardCentering = setBoardCentering
        self.onSetSheetScale = setSheetScale
        self.onSetDrawerStyle = setDrawerStyle
    }

    public var motionPreference: MotionPreference { readMotionPreference() }
    public var deskSwitcherAlignment: DeskSwitcherAlignment { readDeskSwitcherAlignment() }
    public var boardCentering: FocusedBoardCentering { readBoardCentering() }
    public var sheetScale: Int { readSheetScale() }
    public var drawerStyle: DrawerStyle { readDrawerStyle() }
    public func setMotionPreference(_ value: MotionPreference) { onSetMotionPreference(value) }
    public func setDeskSwitcherAlignment(_ value: DeskSwitcherAlignment) { onSetDeskSwitcherAlignment(value) }
    public func setBoardCentering(_ value: FocusedBoardCentering) { onSetBoardCentering(value) }
    public func setSheetScale(_ value: Int) { onSetSheetScale(value) }
    public func setDrawerStyle(_ value: DrawerStyle) { onSetDrawerStyle(value) }
}
