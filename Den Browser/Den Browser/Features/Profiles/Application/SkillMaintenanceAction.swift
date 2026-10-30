enum SkillMaintenanceAction {
    case install
    case update

    var command: String {
        switch self {
        case .install:
            "npx --yes skills@latest add nekonata-team/den-browser --skill den --global"
        case .update:
            "npx --yes skills@latest update den --global"
        }
    }
}
