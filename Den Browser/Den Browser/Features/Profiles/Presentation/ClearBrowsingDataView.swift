import SwiftUI

struct ClearBrowsingDataView: View {
    let profileID: UUID
    let onDismiss: () -> Void

    @Environment(ProfileManager.self) private var profileManager
    @State private var selectedCategories: Set<BrowsingDataCategory> = Set(BrowsingDataCategory.allCases)
    @State private var isClearing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let profile = profileManager.profile(id: profileID) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(profile.color.color)
                        .frame(width: 12, height: 12)
                    Text("Clear Browsing Data for \(profile.name)")
                        .font(.headline)
                }

                Text("Select the types of browsing data you want to clear for this profile.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(BrowsingDataCategory.allCases) { category in
                        Toggle(isOn: binding(for: category)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.label)
                                    .font(.body)
                                Text(category.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(.vertical, 4)

                HStack {
                    Spacer()
                    Button("Cancel") {
                        onDismiss()
                    }
                    .disabled(isClearing)

                    Button("Clear Data", role: .destructive) {
                        clearData()
                    }
                    .disabled(selectedCategories.isEmpty || isClearing)
                }
            } else {
                Text("Profile not found")
                    .font(.headline)
                HStack {
                    Spacer()
                    Button("Close") {
                        onDismiss()
                    }
                }
            }
        }
        .padding()
        .frame(width: 420)
    }

    private func binding(for category: BrowsingDataCategory) -> Binding<Bool> {
        Binding(
            get: { selectedCategories.contains(category) },
            set: { isSelected in
                if isSelected {
                    selectedCategories.insert(category)
                } else {
                    selectedCategories.remove(category)
                }
            }
        )
    }

    private func clearData() {
        isClearing = true
        Task {
            _ = await profileManager.clearBrowsingData(categories: selectedCategories, profileID: profileID)
            isClearing = false
            onDismiss()
        }
    }
}
