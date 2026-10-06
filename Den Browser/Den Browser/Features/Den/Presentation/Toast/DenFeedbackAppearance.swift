import SFSafeSymbols
import SwiftUI

func feedbackSymbol(for severity: DenFeedback.Severity) -> SFSymbol {
    switch severity {
    case .success: .checkmarkCircleFill
    case .info: .infoCircleFill
    case .warning: .exclamationmarkTriangleFill
    case .error: .xmarkOctagonFill
    }
}

func feedbackIconColor(for severity: DenFeedback.Severity) -> Color {
    switch severity {
    case .success: .green
    case .info: .secondary
    case .warning: .orange
    case .error: .red
    }
}
