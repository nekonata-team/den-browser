import DenDesign
import DenDomain
import Foundation
import SFSafeSymbols
import SwiftUI

struct NotificationListView: View {
    let profileColor: Color

    @Environment(NotificationListViewModel.self) private var viewModel

    var body: some View {
        let items = viewModel.items
        let unreadCount = viewModel.unreadCount

        VStack(alignment: .leading, spacing: DenPanelLayout.contentSpacing) {
            HStack {
                Image(systemSymbol: .bell)
                    .foregroundStyle(.secondary)
                Text("Notifications")
                    .font(.headline)
                Spacer()
                if unreadCount > 0 {
                    Text("\(unreadCount) unread")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(role: .destructive) {
                    viewModel.requestClear()
                } label: {
                    Image(systemSymbol: .trash)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .disabled(items.isEmpty)
                .accessibilityLabel("Clear All Notifications")
                .help("Clear All Notifications")
                DenCloseButton(label: "Close Notifications", action: viewModel.close)
            }

            if items.isEmpty {
                ContentUnavailableView("No Notifications", systemSymbol: .bell)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(items) { item in
                                NotificationRow(
                                    item: item,
                                    profileColor: profileColor,
                                    isSelected: item.id == viewModel.selectedNotificationID,
                                    onOpen: { viewModel.open(item.notification) }
                                )
                                .id(item.id)
                            }
                        }
                    }
                    .onChange(of: viewModel.selectedNotificationID) { _, selectedNotificationID in
                        guard let selectedNotificationID else { return }
                        proxy.scrollTo(selectedNotificationID, anchor: .center)
                    }
                }
                .frame(maxHeight: 480)
            }
        }
        .padding(DenPanelLayout.padding)
        .frame(width: 380)
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notification-list")
    }
}

private struct NotificationRow: View {
    let item: NotificationListItem
    let profileColor: Color
    let isSelected: Bool
    let onOpen: () -> Void

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(item.notification.isRead ? Color.clear : profileColor)
                    .frame(width: 8, height: 8)
                    .overlay {
                        Circle().stroke(
                            profileColor.opacity(0.7),
                            lineWidth: item.notification.isRead ? 1 : 0)
                    }
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.notification.title ?? item.notification.body)
                            .font(.callout.weight(item.notification.isRead ? .regular : .semibold))
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        NotificationTime(createdAt: item.notification.createdAt)
                    }

                    if item.notification.title != nil, !item.notification.body.isEmpty {
                        Text(item.notification.body)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }

                    Text(item.source.map { "\($0.deskLabel) · \($0.boardLabel)" } ?? "Board removed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected
                    ? (differentiateWithoutColor ? Color.primary : profileColor).opacity(0.2)
                    : item.notification.isRead
                        ? Color.clear
                        : profileColor.opacity(0.1),
                in: RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? (differentiateWithoutColor ? Color.primary : profileColor.opacity(0.85))
                            : Color.clear,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .opacity(item.source == nil ? 0.55 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.notification.title ?? item.notification.body)
        .accessibilityHint(item.source == nil ? "Board no longer exists" : "Focus notification source Board")
    }
}

private struct NotificationTime: View {
    let createdAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if let relativeTime = relativeTime(now: context.date) {
                Text(relativeTime)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func relativeTime(now: Date) -> String? {
        guard now.timeIntervalSince(createdAt) >= 60 else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: now)
    }
}
