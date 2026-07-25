import SwiftUI

struct ToastMessage: Equatable, Identifiable {
    let id = UUID()
    let message: String
    let style: ToastStyle

    enum ToastStyle: Equatable {
        case success
        case info
        case warning
        case error

        var systemImage: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .info: "info.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "xmark.octagon.fill"
            }
        }

        var iconColor: Color {
            switch self {
            case .success: .green
            case .info: .secondary
            case .warning: .orange
            case .error: .red
            }
        }
    }
}
