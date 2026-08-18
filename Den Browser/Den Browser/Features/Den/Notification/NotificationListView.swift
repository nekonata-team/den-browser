import Foundation
import SwiftUI

struct DenNotification: Equatable, Identifiable {
    let id: UUID
    let title: String?
    let body: String
    let boardID: UUID
    let createdAt: Date
    var isRead: Bool

    init(
        id: UUID = UUID(),
        title: String?,
        body: String,
        boardID: UUID,
        createdAt: Date = .now,
        isRead: Bool = false
    ) {
        self.id = id
        self.title = title?.isEmpty == false ? title : nil
        self.body = body
        self.boardID = boardID
        self.createdAt = createdAt
        self.isRead = isRead
    }
}

struct NotificationListView: View {
    let profileColor: Color

    @Environment(DenStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: DenPanelLayout.contentSpacing) {
            HStack {
                Image(systemName: "bell")
                    .foregroundStyle(.secondary)
                Text("Notifications")
                    .font(.headline)
                Spacer()
                if store.unreadNotificationCount > 0 {
                    Text("\(store.unreadNotificationCount) unread")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(role: .destructive) {
                    store.requestNotificationClearConfirmation()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .disabled(store.notifications.isEmpty)
                .accessibilityLabel("Clear All Notifications")
                .help("Clear All Notifications")
                DenCloseButton(label: "Close Notifications", action: store.closeNotificationList)
            }

            if store.notifications.isEmpty {
                ContentUnavailableView("No Notifications", systemImage: "bell")
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(store.notifications) { notification in
                                Button {
                                    store.openNotification(notification)
                                } label: {
                                    NotificationRow(
                                        notification: notification,
                                        source: store.notificationSource(for: notification),
                                        profileColor: profileColor,
                                        isSelected: notification.id == store.selectedNotificationID)
                                }
                                .buttonStyle(.plain)
                                .id(notification.id)
                            }
                        }
                    }
                    .onChange(of: store.selectedNotificationID) { _, selectedNotificationID in
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
    let notification: DenNotification
    let source: DenNotificationSource?
    let profileColor: Color
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(notification.isRead ? Color.clear : profileColor)
                .frame(width: 8, height: 8)
                .overlay {
                    Circle().stroke(profileColor.opacity(0.7), lineWidth: notification.isRead ? 1 : 0)
                }
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(notification.title ?? notification.body)
                        .font(.callout.weight(notification.isRead ? .regular : .semibold))
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    NotificationTime(createdAt: notification.createdAt)
                }

                if notification.title != nil, !notification.body.isEmpty {
                    Text(notification.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Text(source.map { "\($0.deskLabel) · \($0.boardLabel)" } ?? "Board removed")
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
                ? profileColor.opacity(0.2)
                : notification.isRead
                    ? Color.clear
                    : profileColor.opacity(0.1),
            in: RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(notification.title ?? notification.body)
        .accessibilityHint(source == nil ? "Board no longer exists" : "Focus notification source Board")
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
