import SwiftUI

enum ToastTarget: Equatable {
    case board(UUID)
    case drawerItem(UUID)
}

struct ToastMessage: Equatable, Identifiable {
    let id = UUID()
    let title: String?
    let body: String
    let style: ToastStyle
    let target: ToastTarget?

    var message: String {
        [title, body.isEmpty ? nil : body]
            .compactMap { $0 }
            .joined(separator: ": ")
    }

    init(
        title: String? = nil,
        body: String,
        style: ToastStyle,
        target: ToastTarget? = nil
    ) {
        self.title = title?.isEmpty == false ? title : nil
        self.body = body
        self.style = style
        self.target = target
    }

    init(message: String, style: ToastStyle) {
        self.init(body: message, style: style)
    }

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
