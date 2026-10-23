import AppKit
import DenModels
import Foundation

extension AppearanceModel {
    convenience init(preferences: AppPreferences) {
        self.init(
            motionPreference: { preferences.motionPreference },
            deskSwitcherAlignment: { preferences.deskSwitcherAlignment },
            boardCentering: { preferences.boardCentering },
            sheetScale: { preferences.sheetScale },
            drawerStyle: { preferences.drawerStyle },
            setMotionPreference: { preferences.setMotionPreference($0) },
            setDeskSwitcherAlignment: { preferences.setDeskSwitcherAlignment($0) },
            setBoardCentering: { preferences.setBoardCentering($0) },
            setSheetScale: { preferences.setSheetScale($0) },
            setDrawerStyle: { preferences.setDrawerStyle($0) })
    }
}

extension ShortcutSettingsModel {
    convenience init(preferences: AppPreferences) {
        self.init(
            shortcutOverrides: { preferences.shortcutOverrides },
            deskNumberBinding: { preferences.deskNumberBinding },
            shortcut: { preferences.shortcut(for: $0) },
            setShortcut: { preferences.setShortcut($0, for: $1) },
            hasShortcutOverride: { preferences.hasShortcutOverride(for: $0) },
            resetShortcut: { preferences.resetShortcut(for: $0) },
            clearShortcut: { preferences.clearShortcut(for: $0) },
            setDeskNumberBinding: { preferences.setDeskNumberBinding($0) },
            hasDeskNumberBindingOverride: { preferences.hasDeskNumberBindingOverride() },
            resetDeskNumberBinding: { preferences.resetDeskNumberBinding() },
            clearDeskNumberBinding: { preferences.clearDeskNumberBinding() },
            resetAllShortcuts: { preferences.resetAllShortcuts() })
    }
}
extension TerminalSettingsModel {
    convenience init(preferences: AppPreferences) {
        self.init(
            zellijPath: { preferences.zellijPath }, zmxPath: { preferences.zmxPath },
            saveZellijPath: { preferences.setZellijPath($0) }, saveZmxPath: { preferences.setZmxPath($0) },
            openPermissions: {
                guard
                    let url = URL(
                        string:
                            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")
                else { return }
                NSWorkspace.shared.open(url)
            })
    }
}
extension ProfileSettingsModel {
    convenience init(manager: ProfileManager) {
        self.init(
            profiles: { manager.profiles }, error: { manager.errorMessage },
            canDelete: { manager.canDeleteProfile($0) }, create: { manager.createProfile(name: $0, color: $1) },
            update: { manager.updateProfile($0, name: $1, color: $2) }, delete: { await manager.deleteProfile($0) },
            dismissError: { manager.clearError() },
            clearSelection: {
                manager.clearBrowsingDataWindowID == nil ? manager.clearBrowsingDataProfileID : nil
            },
            requestClear: {
                manager.clearBrowsingDataProfileID = $0
                manager.clearBrowsingDataWindowID = nil
            },
            dismissClear: {
                manager.clearBrowsingDataProfileID = nil
                manager.clearBrowsingDataWindowID = nil
            }, clear: { await manager.clearBrowsingData(categories: $0, profileID: $1) })
    }
}
extension SheetNavigationSettingsModel {
    convenience init(manager: SheetNavigationManager) {
        self.init(
            isEnabled: { manager.isEnabled }, hintAlphabet: { manager.hintAlphabet },
            ignoredHosts: { manager.ignoredHosts }, setEnabled: { manager.setEnabled($0) },
            setHintAlphabet: { manager.setHintAlphabet($0) }, setIgnoredSites: { manager.setIgnoredSites($0) },
            normalizeAlphabet: { SheetNavigationManager.normalizeHintAlphabet($0) },
            normalizeHosts: { SheetNavigationManager.normalizeIgnoredSites($0) })
    }
}
extension DefaultBrowserSettingsModel {
    convenience init(preferences: AppPreferences) {
        self.init(
            destination: { preferences.externalLinkDestination },
            setDestination: { preferences.setExternalLinkDestination($0) },
            loadStatus: { await Task.detached(priority: .userInitiated) { DefaultBrowserSystem.status() }.value },
            setDefault: { await DefaultBrowserSystem.makeDefault() })
    }
}

extension WebSettingsModel {
    init(preferences: AppPreferences, manager: ProfileManager) {
        self.init(
            searchEngine: { preferences.searchEngine },
            automaticPIPOnDeskSwitch: { preferences.automaticPIPOnDeskSwitch },
            uBOLiteEnabled: { preferences.uBOLiteEnabled }, isInstalled: { manager.uboliteInstaller.isInstalled },
            installedVersion: { manager.uboliteInstaller.installedVersion },
            isBusy: { manager.uboliteInstaller.isBusy },
            errorMessage: {
                if case .error(let message) = manager.uboliteInstaller.state { return message }
                return nil
            },
            setSearchEngine: { preferences.setSearchEngine($0) },
            setAutomaticPIPOnDeskSwitch: { preferences.setAutomaticPIPOnDeskSwitch($0) },
            setUBOLiteEnabled: { manager.setUBOLiteEnabled($0) }, openOptions: { manager.presentUBOLiteOptions() },
            update: { await manager.updateUBOLite() },
            install: { if await manager.uboliteInstaller.install() { manager.setUBOLiteEnabled(true) } },
            uninstall: {
                manager.setUBOLiteEnabled(false)
                manager.uboliteInstaller.uninstall()
            })
    }
}
