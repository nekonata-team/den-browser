public import DenDomain
public import Foundation

public enum DeskPresetSelection: Hashable {
    case builtIn(BuiltInDeskPreset)
    case personal(UUID)
    case newDesk(label: String)
}
