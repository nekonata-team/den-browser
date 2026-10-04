import WebKit

extension WebProfileStore {
    var websiteDataStore: WKWebsiteDataStore {
        switch self {
        case .default:
            .default()
        case .identified(let identifier):
            WKWebsiteDataStore(forIdentifier: identifier)
        }
    }
}

extension BrowsingDataCategory {
    var websiteDataTypes: Set<String> {
        switch self {
        case .cookies:
            [WKWebsiteDataTypeCookies]
        case .cache:
            [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache]
        case .localData:
            [
                WKWebsiteDataTypeLocalStorage,
                WKWebsiteDataTypeIndexedDBDatabases,
                WKWebsiteDataTypeWebSQLDatabases,
            ]
        }
    }
}

extension Collection where Element == BrowsingDataCategory {
    var websiteDataTypes: Set<String> {
        Set(flatMap(\.websiteDataTypes))
    }
}
