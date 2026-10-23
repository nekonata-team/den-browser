import DenDomain
import DenModels
import Foundation
import Testing

@MainActor
struct DownloadActivityModelTests {
    @Test func concurrentDownloadsUpdateAndEndIndependently() {
        // Arrange
        let model = DownloadActivityModel()
        let first = DownloadActivity(filename: "first.zip")
        let second = DownloadActivity(filename: "second.zip")
        model.receive(.started(first))
        model.receive(.started(second))

        // Act
        model.receive(.progressed(id: first.id, fractionCompleted: 0.5))
        model.receive(.ended(id: first.id))

        // Assert
        #expect(model.activities == [second])
    }
}
