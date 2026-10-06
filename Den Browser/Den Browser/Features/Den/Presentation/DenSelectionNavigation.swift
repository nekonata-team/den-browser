import Foundation

enum DenSelectionNavigation {
    static func next<Value: Equatable>(_ selection: Value?, among values: [Value], by offset: Int) -> Value? {
        guard !values.isEmpty else { return nil }
        guard let currentIndex = selection.flatMap(values.firstIndex(of:)) else {
            return offset < 0 ? values.last : values.first
        }
        let count = values.count
        return values[(currentIndex + offset % count + count) % count]
    }
}
