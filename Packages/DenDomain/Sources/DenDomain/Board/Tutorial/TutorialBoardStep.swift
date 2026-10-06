import Foundation

public enum TutorialBoardStep: CaseIterable, Hashable {
    case openBoard, navigateBoards, createDesk, keyboardShortcuts, terminalBoard

    public var isRequired: Bool { self != .keyboardShortcuts && self != .terminalBoard }

    public static var requiredSteps: [Self] { allCases.filter(\.isRequired) }
}
