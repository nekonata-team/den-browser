public import SwiftUI

extension View {
    public func terminalFontZoom(
        isEnabled: Bool = true,
        onStart: @escaping () -> Void,
        onAdjustFontSize: @escaping (Int) -> Int
    ) -> some View {
        modifier(
            TerminalFontZoomModifier(
                isEnabled: isEnabled,
                onStart: onStart,
                onAdjustFontSize: onAdjustFontSize
            )
        )
    }
}

private struct TerminalFontZoomModifier: ViewModifier {
    let isEnabled: Bool
    let onStart: () -> Void
    let onAdjustFontSize: (Int) -> Int

    @State private var isMagnifying = false
    @State private var appliedFontSizeSteps = 0

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            MagnifyGesture(minimumScaleDelta: 0.01)
                .onChanged { value in
                    guard isEnabled else { return }
                    if !isMagnifying {
                        isMagnifying = true
                        appliedFontSizeSteps = 0
                        onStart()
                    }

                    let targetSteps = Int(
                        ((value.magnification - 1) / 0.1).rounded(.towardZero)
                    )
                    let delta = targetSteps - appliedFontSizeSteps
                    guard delta != 0 else { return }
                    appliedFontSizeSteps += onAdjustFontSize(delta)
                }
                .onEnded { _ in
                    isMagnifying = false
                    appliedFontSizeSteps = 0
                }
        )
    }
}
