import DenDomain
import Foundation
import Observation

@MainActor
@Observable
public final class DownloadActivityModel {
    public private(set) var activities: [DownloadActivity] = []

    public init() {}

    public func receive(_ event: DownloadActivityEvent) {
        switch event {
        case .started(let activity):
            if let index = activities.firstIndex(where: { $0.id == activity.id }) {
                activities[index] = activity
            } else {
                activities.append(activity)
            }
        case .progressed(let id, let fractionCompleted):
            guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
            activities[index].fractionCompleted = fractionCompleted
        case .ended(let id):
            activities.removeAll { $0.id == id }
        }
    }
}
