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
    static let defaultFallbackDownloadURL: URL = {
        guard
            let url = URL(
                string:
                    "https://github.com/uBlockOrigin/uBOL-home/releases/download/2026.901.1442/uBOLite_2026.901.1442.safari.zip"
            )
        else {
            preconditionFailure("Invalid default uBlock Origin Lite download URL")
        }
        return url
    }()

    let identifier: String
    let directoryURL: URL
    let releaseAPIURL: URL
    let fallbackDownloadURL: URL

    private(set) var state: State = .idle
    private(set) var isInstalled: Bool = false
    private(set) var installedVersion: String?
    private let session: URLSession

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
        fallbackDownloadURL: URL = UBOLiteInstaller.defaultFallbackDownloadURL,
        session: URLSession = .shared
    ) {
        self.identifier = identifier
        self.directoryURL = directoryURL
        self.releaseAPIURL = releaseAPIURL
        self.fallbackDownloadURL = fallbackDownloadURL
        self.session = session
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

    private func resolveDownloadURL() async -> URL {
        var request = URLRequest(url: releaseAPIURL)
        request.setValue("DenBrowser", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let assets = json["assets"] as? [[String: Any]]
            {
                for asset in assets {
                    if let name = asset["name"] as? String,
                        name.hasPrefix("uBOLite_") && name.hasSuffix(".safari.zip"),
                        let downloadURLString = asset["browser_download_url"] as? String,
                        let url = URL(string: downloadURLString)
                    {
                        return url
                    }
                }
            }
        } catch {}
        return fallbackDownloadURL
    }

    @discardableResult
    func install() async -> Bool {
        guard !isBusy else { return false }
        state = .downloading(progress: nil)

        do {
            let targetURL = await resolveDownloadURL()
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

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", tempZipURL.path, unpackDir.path]
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw NSError(
                    domain: "UBOLiteInstaller",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: "Failed to decompress uBlock Origin Lite archive."]
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

            let parentDir = directoryURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: directoryURL.path) {
                try FileManager.default.removeItem(at: directoryURL)
            }
            try FileManager.default.moveItem(at: unpackDir, to: directoryURL)

            refreshInstalledStatus()
            state = .idle
            return isInstalled
        } catch {
            state = .error(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func uninstall() -> Bool {
        if FileManager.default.fileExists(atPath: directoryURL.path) {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        refreshInstalledStatus()
        state = .idle
        return true
    }

    var descriptor: WebExtensionDescriptor? {
        guard isInstalled else { return nil }
        return WebExtensionDescriptor(
            identifier: identifier,
            directoryURL: directoryURL,
            preapproveRequestedAccess: true
        )
    }
}
