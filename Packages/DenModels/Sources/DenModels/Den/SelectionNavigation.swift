import Foundation

public enum SelectionNavigation {
    /// Moves through candidates with wrapping; do not use for bounded movement or reordering.
    ///
    /// Empty candidates return nil. A missing selection starts at the last item for a negative
    /// offset, otherwise the first; `values` must follow the displayed candidate order.
    public static func next<Value: Equatable>(_ selection: Value?, among values: [Value], by offset: Int) -> Value? {
        guard !values.isEmpty else { return nil }
        guard let currentIndex = selection.flatMap(values.firstIndex(of:)) else {
            return offset < 0 ? values.last : values.first
        }
        let count = values.count
        return values[(currentIndex + offset % count + count) % count]
    }
}
