import DenDomain
import Foundation

@MainActor
final class RuntimeWindowConnection {
    weak var controller: DenController?

    func disconnect() {
        if let controller {
            for activity in controller.activeDownloads { controller.handleDownloadActivity(.ended(id: activity.id)) }
        }
        controller = nil
    }
}
