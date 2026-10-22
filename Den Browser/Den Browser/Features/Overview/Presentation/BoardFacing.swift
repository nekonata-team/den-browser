import AppKit
import DenDomain
import DenViews
import SFSafeSymbols
import SwiftUI

enum BoardFacingColors {
    static let web = Color.blue
    static let terminal = Color.orange
    static let tutorial = Color.purple
    static let inspection = Color.purple
}

/// The core presentation of a Board Facing maintaining proper aspect-ratio width.
struct BoardFacing: View {
    let displayName: String
    let width: Double
    let symbol: SFSymbol
    let kindLabel: String
    let typeColor: Color
    let detailText: String
    let facing: NSImage?
    var boardHeight: CGFloat = DenLayout.fallbackBoardHeight
    var facingHeight: CGFloat = DenLayout.overviewFacingHeight
    var scale: CGFloat = 1

    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption2) private var caption2Size: CGFloat = 11

    private var facingWidth: CGFloat {
        let referenceHeight = max(boardHeight, DenLayout.minimumBoardHeight)
        return CGFloat(width) * facingHeight / referenceHeight * scale
    }

    private var boardTypeIcon: some View {
        Image(systemSymbol: symbol)
            .font(.system(size: captionSize * scale, weight: .semibold))
            .foregroundStyle(typeColor)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let facing {
                Image(nsImage: facing)
                    .resizable()
                    .scaledToFit()
                    .frame(width: facingWidth, height: facingHeight * scale, alignment: .center)
                    .clipped()
                    .opacity(0.85)

                VStack {
                    Spacer()
                    HStack(spacing: 4 * scale) {
                        boardTypeIcon
                        Text(displayName)
                            .font(.system(size: caption2Size * scale, weight: .semibold))
                            .lineLimit(1)
                            .foregroundStyle(.white)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 6 * scale)
                    .padding(.vertical, 4 * scale)
                    .background(Color.black.opacity(0.65))
                }
            } else {
                VStack(alignment: .leading, spacing: 6 * scale) {
                    HStack(spacing: 6 * scale) {
                        boardTypeIcon
                            .accessibilityHidden(true)

                        Text(kindLabel)
                            .font(.system(size: caption2Size * scale, weight: .medium))
                            .foregroundStyle(typeColor)
                    }

                    Text(displayName)
                        .font(.system(size: captionSize * scale, weight: .semibold))
                        .lineLimit(2)

                    if !detailText.isEmpty {
                        Text(detailText)
                            .font(.system(size: caption2Size * scale))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Capsule()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(maxWidth: .infinity)
                        .frame(height: 3 * scale)
                }
                .padding(8 * scale)
            }
        }
        .frame(
            width: facingWidth,
            height: facingHeight * scale,
            alignment: .leading
        )
        .foregroundStyle(.primary)
        .background(
            typeColor.opacity(0.09),
            in: RoundedRectangle(cornerRadius: DenRadius.small * scale, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: DenRadius.small * scale, style: .continuous))
    }
}

/// Overview-specific Board Facing wrapper handling selection, anchor badge, and frame styling.
struct OverviewBoardFacing: View {
    let board: BoardState
    var isSelected: Bool = false
    var isAnchor: Bool = false
    var isMaximized: Bool = false
    var maximizedBoardWidth: CGFloat?
    var profileColor: Color = .blue
    var boardHeight: CGFloat = DenLayout.fallbackBoardHeight
    var facingHeight: CGFloat = DenLayout.overviewFacingHeight
    var facing: NSImage?
    var scale: CGFloat = 1

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @ScaledMetric(relativeTo: .caption2) private var caption2Size: CGFloat = 11

    private var effectiveBoardWidth: Double {
        if isMaximized, let maximizedBoardWidth {
            return Double(maximizedBoardWidth)
        }
        return board.width
    }

    private var selectionBorderColor: Color {
        if isSelected {
            return differentiateWithoutColor ? Color.primary : profileColor.opacity(DenSurfaceColors.emphasisOpacity)
        }
        return Color.primary.opacity(0.12)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            BoardFacing(
                displayName: board.displayName,
                width: effectiveBoardWidth,
                symbol: boardSymbol(for: board.kind),
                kindLabel: Self.kindLabel(for: board),
                typeColor: Self.typeColor(for: board),
                detailText: Self.detailText(for: board),
                facing: facing,
                boardHeight: boardHeight,
                facingHeight: facingHeight,
                scale: scale
            )
            .background(
                isSelected
                    ? (differentiateWithoutColor ? Color.primary : profileColor).opacity(
                        DenSurfaceColors.selectionOpacity) : Color.clear,
                in: RoundedRectangle(cornerRadius: DenRadius.small * scale, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DenRadius.small * scale, style: .continuous)
                    .stroke(selectionBorderColor, lineWidth: (isSelected ? 2 : 1) * scale)
            }

            if isAnchor {
                Image(systemSymbol: .pinFill)
                    .font(.system(size: caption2Size * scale))
                    .foregroundStyle(facing != nil ? Color.white.opacity(0.8) : Color.secondary)
                    .padding(6 * scale)
            }
        }
    }

    static func kindLabel(for board: BoardState) -> String {
        if board.isInspection { return "Inspection" }
        if board.isTutorial { return "Tutorial" }
        if board.isZmx { return "zmx" }
        if board.isZellij { return "Zellij" }
        if board.isTerminal { return "Terminal" }
        return "Web"
    }

    static func typeColor(for board: BoardState) -> Color {
        if board.isInspection { return BoardFacingColors.inspection }
        if board.isTutorial { return BoardFacingColors.tutorial }
        return board.isTerminal ? BoardFacingColors.terminal : BoardFacingColors.web
    }

    static func detailText(for board: BoardState) -> String {
        if board.isTutorial { return "Interactive checklist" }
        return board.zmxSessionName
            ?? board.zellijSessionName
            ?? board.terminalWorkingDirectory
            ?? board.currentSheetURL?.host(percentEncoded: false)
            ?? board.currentSheetURL?.absoluteString
            ?? ""
    }
}

/// Preset preview Board Facing wrapper adapting DeskPresetBoard to BoardFacing.
struct DeskPresetBoardFacing: View {
    let board: DeskPresetBoard
    var boardHeight: CGFloat = DenLayout.fallbackBoardHeight
    var facingHeight: CGFloat = DenPanelLayout.presetFacingHeight
    var facing: NSImage?

    var body: some View {
        BoardFacing(
            displayName: board.customLabel ?? board.label,
            width: board.width,
            symbol: Self.symbol(for: board),
            kindLabel: Self.kindLabel(for: board),
            typeColor: Self.typeColor(for: board.kind),
            detailText: Self.detailText(for: board),
            facing: facing,
            boardHeight: boardHeight,
            facingHeight: facingHeight
        )
        .overlay {
            RoundedRectangle(cornerRadius: DenRadius.small, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        }
    }

    private static func kindLabel(for board: DeskPresetBoard) -> String {
        switch board.kind {
        case .web: return "Web"
        case .inspection: return "Inspection"
        case .terminal:
            if board.zmxSessionName != nil { return "zmx" }
            if board.zellijSessionName != nil { return "Zellij" }
            return "Terminal"
        }
    }

    private static func typeColor(for kind: DeskPresetBoardKind) -> Color {
        switch kind {
        case .web: return BoardFacingColors.web
        case .inspection: return BoardFacingColors.inspection
        case .terminal: return BoardFacingColors.terminal
        }
    }

    private static func symbol(for board: DeskPresetBoard) -> SFSymbol {
        switch board.kind {
        case .web: return .globe
        case .inspection: return .magnifyingglass
        case .terminal:
            if board.zmxSessionName != nil { return .appleTerminalOnRectangle }
            if board.zellijSessionName != nil { return .rectangle3Group }
            return .appleTerminal
        }
    }

    private static func detailText(for board: DeskPresetBoard) -> String {
        guard case .inspection = board.kind else {
            return board.initialSheetURL?.host(percentEncoded: false)
                ?? board.zmxSessionName
                ?? board.zellijSessionName
                ?? board.terminalWorkingDirectory
                ?? ""
        }
        return "Inspection Board"
    }
}
