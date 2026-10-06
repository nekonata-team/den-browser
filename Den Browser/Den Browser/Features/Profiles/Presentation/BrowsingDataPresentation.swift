func browsingDataLabel(for category: BrowsingDataCategory) -> String {
    switch category {
    case .cookies: "Cookies and Site Data"
    case .cache: "Cached Images and Files"
    case .localData: "Local Storage and Databases"
    }
}

func browsingDataDescription(for category: BrowsingDataCategory) -> String {
    switch category {
    case .cookies: "Signs you out of most web sites."
    case .cache: "Frees up disk space and forces fresh site resources to load."
    case .localData: "Clears offline site data and saved web application states."
    }
}
