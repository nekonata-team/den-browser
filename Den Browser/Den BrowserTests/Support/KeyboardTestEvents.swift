import AppKit
import Testing

@MainActor
func keyEvent(
    characters: String,
    charactersIgnoringModifiers: String,
    modifiers: NSEvent.ModifierFlags = [],
    isARepeat: Bool = false,
    keyCode: UInt16,
    windowNumber: Int = 0
) throws -> NSEvent {
    try #require(
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers, isARepeat: isARepeat, keyCode: keyCode))
}

@MainActor
func keyEvent(
    _ character: String,
    keyCode: UInt16,
    modifiers: NSEvent.ModifierFlags = [],
    charactersIgnoringModifiers: String? = nil,
    windowNumber: Int = 0
) throws -> NSEvent {
    try keyEvent(
        characters: character, charactersIgnoringModifiers: charactersIgnoringModifiers ?? character,
        modifiers: modifiers, keyCode: keyCode, windowNumber: windowNumber)
}

@MainActor
func keyEvent(_ specialKey: NSEvent.SpecialKey, keyCode: UInt16) throws -> NSEvent {
    let scalar = try #require(UnicodeScalar(specialKey.rawValue))
    return try keyEvent(String(scalar), keyCode: keyCode)
}

@MainActor
func arrowEvent(
    _ specialKey: NSEvent.SpecialKey,
    modifiers: NSEvent.ModifierFlags,
    isARepeat: Bool = false
) throws -> NSEvent {
    let keyCode: UInt16 =
        switch specialKey {
        case .upArrow: 126
        case .downArrow: 125
        case .leftArrow: 123
        case .rightArrow: 124
        default: preconditionFailure("Expected an arrow key")
        }
    let scalar = try #require(UnicodeScalar(specialKey.rawValue))
    return try keyEvent(
        characters: String(scalar), charactersIgnoringModifiers: String(scalar),
        modifiers: modifiers, isARepeat: isARepeat, keyCode: keyCode)
}
