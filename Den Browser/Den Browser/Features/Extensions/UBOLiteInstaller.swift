import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class UBOLiteInstaller {
    enum State: Equatable {
        case idle
        case downloading(progress: Double?)
        case unpacking
        case error(String)
    }

    static let defaultIdentifier = "com.denbrowser.ubolite"
    static let defaultReleaseAPIURL: URL = {
        guard let url = URL(string: "https://api.github.com/repos/uBlockOrigin/uBOL-home/releases/latest") else {
            preconditionFailure("Invalid default GitHub release API URL")
        }
        return url
    }()
    let identifier: String
    let directoryURL: URL
    let releaseAPIURL: URL

    private(set) var state: State = .idle
    private(set) var isInstalled: Bool = false
    private(set) var installedVersion: String?
    private let session: URLSession
    private let commandRunner: any TerminalCommandRunning

    var isBusy: Bool {
        switch state {
        case .downloading, .unpacking: true
        case .idle, .error: false
        }
    }

    init(
        identifier: String = UBOLiteInstaller.defaultIdentifier,
        directoryURL: URL = UBOLiteInstaller.defaultDirectoryURL(),
        releaseAPIURL: URL = UBOLiteInstaller.defaultReleaseAPIURL,
        session: URLSession = .shared,
        commandRunner: any TerminalCommandRunning = SubprocessCommandRunner()
    ) {
        self.identifier = identifier
        self.directoryURL = directoryURL
        self.releaseAPIURL = releaseAPIURL
        self.session = session
        self.commandRunner = commandRunner
        refreshInstalledStatus()
    }

    static func defaultDirectoryURL() -> URL {
        let appSupport =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return
            appSupport
            .appending(path: "Den Browser", directoryHint: .isDirectory)
            .appending(path: "Extensions", directoryHint: .isDirectory)
            .appending(path: defaultIdentifier, directoryHint: .isDirectory)
    }

    func refreshInstalledStatus() {
        let manifestURL = directoryURL.appending(path: "manifest.json")
        isInstalled = FileManager.default.fileExists(atPath: manifestURL.path)
        if isInstalled,
            let data = try? Data(contentsOf: manifestURL),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let version = json["version"] as? String
        {
            installedVersion = version
        } else {
            installedVersion = nil
        }
    }

    private func resolveDownloadURL() async throws -> URL {
        var request = URLRequest(url: releaseAPIURL)
        request.setValue("DenBrowser", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let assets = json["assets"] as? [[String: Any]]
        else {
            throw URLError(.cannotParseResponse)
        }
        for asset in assets {
            if let name = asset["name"] as? String,
                name.hasPrefix("uBOLite_") && name.hasSuffix(".safari.zip"),
                let downloadURLString = asset["browser_download_url"] as? String,
                let url = URL(string: downloadURLString)
            {
                return url
            }
        }
        throw URLError(.resourceUnavailable)
    }

    @discardableResult
    func install() async -> Bool {
        guard !isBusy else { return false }
        state = .downloading(progress: nil)

        do {
            let targetURL = try await resolveDownloadURL()
            var request = URLRequest(url: targetURL)
            request.setValue("DenBrowser", forHTTPHeaderField: "User-Agent")

            let (tempZipURL, response) = try await session.download(for: request)
            defer { try? FileManager.default.removeItem(at: tempZipURL) }

            if let http = response as? HTTPURLResponse, http.statusCode < 200 || http.statusCode >= 300 {
                throw NSError(
                    domain: "UBOLiteInstaller",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "Download failed with HTTP status \(http.statusCode)."]
                )
            }

            state = .unpacking
            let unpackDir = FileManager.default.temporaryDirectory
                .appending(path: "ubolite-unpack-\(UUID().uuidString)", directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: unpackDir) }

            try FileManager.default.createDirectory(at: unpackDir, withIntermediateDirectories: true)

            let result = try await commandRunner.run(
                executablePath: "/usr/bin/ditto",
                arguments: ["-x", "-k", tempZipURL.path, unpackDir.path],
                timeout: .seconds(60))
            guard result.terminationStatus == 0 else {
                let diagnostic = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = diagnostic.isEmpty ? "" : ": \(diagnostic)"
                throw NSError(
                    domain: "UBOLiteInstaller",
                    code: Int(result.terminationStatus),
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Failed to decompress uBlock Origin Lite archive\(suffix)."
                    ]
                )
            }

            let manifestURL = unpackDir.appending(path: "manifest.json")
            guard FileManager.default.fileExists(atPath: manifestURL.path) else {
                throw NSError(
                    domain: "UBOLiteInstaller",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid extension archive: manifest.json not found."]
                )
            }
            let candidateVersion = try readCandidateVersion(at: manifestURL)
            if let installedVersion, !isNewer(candidateVersion, than: installedVersion) {
                throw NSError(
                    domain: "UBOLiteInstaller",
                    code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Downloaded extension version \(candidateVersion) is not newer than the installed version \(installedVersion)."
                    ]
                )
            }

            let parentDir = directoryURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            var backupURL: URL?
            if FileManager.default.fileExists(atPath: directoryURL.path) {
                let backup = parentDir.appending(
                    path: ".ubolite-backup-\(UUID().uuidString)",
                    directoryHint: .isDirectory)
                try FileManager.default.moveItem(at: directoryURL, to: backup)
                backupURL = backup
            }
            do {
                try FileManager.default.moveItem(at: unpackDir, to: directoryURL)
            } catch {
                if let backupURL {
                    try? FileManager.default.moveItem(at: backupURL, to: directoryURL)
                }
                throw error
            }
            if let backupURL {
                try? FileManager.default.removeItem(at: backupURL)
            }

            refreshInstalledStatus()
            state = .idle
            return isInstalled
        } catch is CancellationError {
            state = .idle
            return false
        } catch {
            state = .error(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func uninstall() -> Bool {
        do {
            if FileManager.default.fileExists(atPath: directoryURL.path) {
                try FileManager.default.removeItem(at: directoryURL)
            }
            refreshInstalledStatus()
            state = .idle
            return !isInstalled
        } catch {
            refreshInstalledStatus()
            state = .error(error.localizedDescription)
            return false
        }
    }

    var descriptor: WebExtensionDescriptor? {
        guard isInstalled else { return nil }
        return WebExtensionDescriptor(
            identifier: identifier,
            directoryURL: directoryURL,
            preapproveRequestedAccess: true
        )
    }

    private func readCandidateVersion(at manifestURL: URL) throws -> String {
        guard
            let json = try? JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any],
            json["manifest_version"] as? Int == 3,
            let name = json["name"] as? String,
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let version = json["version"] as? String,
            Self.versionComponents(version) != nil,
            let background = json["background"] as? [String: Any],
            let scripts = background["scripts"] as? [String],
            !scripts.isEmpty,
            scripts.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else {
            throw NSError(
                domain: "UBOLiteInstaller",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Invalid extension archive manifest."])
        }
        return version
    }

    private func isNewer(_ candidate: String, than installed: String) -> Bool {
        guard let candidate = Self.versionComponents(candidate),
            let installed = Self.versionComponents(installed)
        else {
            return true
        }

        for index in 0..<max(candidate.count, installed.count) {
            let candidateComponent = index < candidate.count ? candidate[index] : 0
            let installedComponent = index < installed.count ? installed[index] : 0
            if candidateComponent != installedComponent {
                return candidateComponent > installedComponent
            }
        }
        return false
    }

    private static func versionComponents(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }

        let components = parts.compactMap { part -> Int? in
            guard part.count <= 5,
                !part.isEmpty,
                part.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
                let value = Int(part),
                value <= 65_535
            else {
                return nil
            }
            return value
        }
        return components.count == parts.count ? components : nil
    }
}
