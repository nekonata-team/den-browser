import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DenControllerDownloadTests {
    @Test func concurrentDownloadsUpdateAndEndIndependently() {
        withTestController { controller in
            // Arrange
            let first = DownloadActivity(filename: "first.zip")
            let second = DownloadActivity(filename: "second.zip")
            controller.handleDownloadActivity(.started(first))
            controller.handleDownloadActivity(.started(second))

            // Act
            controller.handleDownloadActivity(.progressed(id: first.id, fractionCompleted: 0.5))
            controller.handleDownloadActivity(.ended(id: first.id))

            // Assert
            #expect(controller.activeDownloads == [second])
        }
    }
}
