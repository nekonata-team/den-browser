import DenDomain
import DenPresentationModels
import Testing

@MainActor
struct FeedbackModelTests {
    @Test func invalidFeedbackAndNotificationClearPreserveUnrelatedWindowFeedback() {
        // Arrange
        let first = FeedbackModel()
        let second = FeedbackModel()
        // Act
        first.publish(title: nil, body: "Notification", target: .notification(.init()))
        second.publish(title: nil, body: "Board", target: .board(BoardID()))
        let invalid = second.publish(title: "", body: "")
        let cleared = first.clearNotification()
        let unrelated = second.clearNotification()
        // Assert
        #expect(invalid == nil)
        #expect(cleared)
        #expect(first.latest == nil)
        #expect(!unrelated)
        #expect(second.latest?.body == "Board")
    }
}
