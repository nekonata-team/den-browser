import DenDomain
import Foundation
import WebKit

enum DownloadActivityEvent: Equatable {
    case started(DownloadActivity)
    case progressed(id: UUID, fractionCompleted: Double?)
    case ended(id: UUID)
}

@MainActor
final class DownloadHandler: NSObject, WKDownloadDelegate {
    private weak var webView: WKWebView?
    var onActivity: (DownloadActivityEvent) -> Void = { _ in }
    var onFinished: (String) -> Void = { _ in }
    var onFailed: (String) -> Void = { _ in }

    let saveDialogs = DownloadSaveDialogs()
    private var pendingDownloads: [ObjectIdentifier: PendingDownload] = [:]
    private var downloadProgressObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]

    var activeActivities: [DownloadActivity] {
        pendingDownloads.values.map(\.activity)
    }

    init(webView: WKWebView? = nil) {
        self.webView = webView
        super.init()
    }

    func dispose() {
        saveDialogs.cancelAll()
        cleanupAllPendingDownloads()
    }

    struct PendingDownload: Equatable {
        let activityID: UUID
        let destinationURL: URL
        let temporaryURL: URL
        let allowsOverwrite: Bool
        var fractionCompleted: Double?

        var activity: DownloadActivity {
            DownloadActivity(
                id: activityID,
                filename: destinationURL.lastPathComponent,
                fractionCompleted: fractionCompleted)
        }
    }

    func cleanupAllPendingDownloads() {
        for key in Array(pendingDownloads.keys) {
            guard let pending = removePendingDownload(for: key) else { continue }
            try? FileManager.default.removeItem(at: pending.temporaryURL)
        }
    }

    // MARK: - WKDownloadDelegate

    static func temporaryDownloadURL(for destinationURL: URL) -> URL {
        let directory = destinationURL.deletingLastPathComponent()
        let filename = destinationURL.lastPathComponent
        let uniqueID = UUID().uuidString
        return directory.appending(path: ".\(filename).\(uniqueID).download")
    }

    static func finalizeDownload(from temporaryURL: URL, to destinationURL: URL, allowsOverwrite: Bool = true) throws {
        let fileManager = FileManager.default
        if allowsOverwrite, (try? fileManager.attributesOfItem(atPath: destinationURL.path)) != nil {
            _ = try fileManager.replaceItemAt(
                destinationURL,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: .withoutDeletingBackupItem
            )
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        }
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
    ) {
        let key = ObjectIdentifier(download)
        saveDialogs.present(
            suggestedFilename: suggestedFilename, downloadKey: key, in: webView?.window
        ) {
            [weak self] destination, overwrite in
            guard let self, let destination else {
                completionHandler(nil)
                return
            }

            let temporaryURL = Self.temporaryDownloadURL(for: destination)
            self.registerPendingDownload(
                for: key,
                destinationURL: destination,
                temporaryURL: temporaryURL,
                allowsOverwrite: overwrite
            )
            self.observeDownloadProgress(download.progress, for: key)
            completionHandler(temporaryURL)
        }
    }

    @discardableResult
    func registerPendingDownload(
        for key: ObjectIdentifier,
        destinationURL: URL,
        temporaryURL: URL,
        allowsOverwrite: Bool = true
    ) -> UUID {
        let activity = DownloadActivity(filename: destinationURL.lastPathComponent)
        pendingDownloads[key] = PendingDownload(
            activityID: activity.id,
            destinationURL: destinationURL,
            temporaryURL: temporaryURL,
            allowsOverwrite: allowsOverwrite,
            fractionCompleted: nil
        )
        onActivity(.started(activity))
        return activity.id
    }

    @discardableResult
    func completeDownload(for key: ObjectIdentifier) -> Bool {
        guard let pending = removePendingDownload(for: key) else { return false }
        do {
            try Self.finalizeDownload(
                from: pending.temporaryURL, to: pending.destinationURL, allowsOverwrite: pending.allowsOverwrite)
            onFinished(pending.destinationURL.lastPathComponent)
            return true
        } catch {
            try? FileManager.default.removeItem(at: pending.temporaryURL)
            onFailed(pending.destinationURL.lastPathComponent)
            return false
        }
    }

    func failDownload(for key: ObjectIdentifier) {
        saveDialogs.cancelAll(for: key)
        guard let pending = removePendingDownload(for: key) else { return }
        try? FileManager.default.removeItem(at: pending.temporaryURL)
        onFailed(pending.destinationURL.lastPathComponent)
    }

    nonisolated static func downloadProgressFraction(_ progress: Progress) -> Double? {
        let fraction = progress.fractionCompleted
        guard !progress.isIndeterminate, fraction.isFinite else { return nil }
        return min(max(fraction, 0), 1)
    }

    private func observeDownloadProgress(_ progress: Progress, for key: ObjectIdentifier) {
        downloadProgressObservations[key] = progress.observe(
            \.fractionCompleted,
            options: [.initial, .new]
        ) { [weak self] progress, _ in
            let fractionCompleted = Self.downloadProgressFraction(progress)
            Task { @MainActor [weak self] in
                self?.updateDownloadProgress(for: key, fractionCompleted: fractionCompleted)
            }
        }
    }

    private func updateDownloadProgress(for key: ObjectIdentifier, fractionCompleted: Double?) {
        guard var pending = pendingDownloads[key] else { return }
        pending.fractionCompleted = fractionCompleted
        pendingDownloads[key] = pending
        onActivity(
            .progressed(id: pending.activityID, fractionCompleted: fractionCompleted))
    }

    private func removePendingDownload(for key: ObjectIdentifier) -> PendingDownload? {
        downloadProgressObservations.removeValue(forKey: key)?.invalidate()
        guard let pending = pendingDownloads.removeValue(forKey: key) else { return nil }
        onActivity(.ended(id: pending.activityID))
        return pending
    }

    func downloadDidFinish(_ download: WKDownload) {
        completeDownload(for: ObjectIdentifier(download))
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        failDownload(for: ObjectIdentifier(download))
    }
}
