import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DenStoreDownloadTests {
    @Test func concurrentDownloadsUpdateAndEndIndependently() {
        withTestStore { store in
            // Arrange
            let first = DownloadActivity(filename: "first.zip")
            let second = DownloadActivity(filename: "second.zip")
            store.handleDownloadActivity(.started(first))
            store.handleDownloadActivity(.started(second))

            // Act
            store.handleDownloadActivity(.progressed(id: first.id, fractionCompleted: 0.5))
            store.handleDownloadActivity(.ended(id: first.id))

            // Assert
            #expect(store.activeDownloads == [second])
        }
    }
}
