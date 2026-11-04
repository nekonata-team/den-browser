import Foundation

public enum DenAPIPolicy {
    public static func isLocalHTML(_ url: URL?) -> Bool {
        guard let url, url.isFileURL,
            url.host == nil || url.host == "" || url.host == "localhost"
        else { return false }
        return ["html", "htm"].contains(url.pathExtension.lowercased())
    }
}
