import Testing

@testable import Den_Browser

@MainActor
struct DenWindowResourcesTests {
    @Test func replacedScreenshotCompletionPreservesWindowCancellation() async {
        // Arrange
        let resources = DenWindowResources()
        let firstStarted = AsyncStream<Void>.makeStream()
        let firstFinished = AsyncStream<Void>.makeStream()
        let secondStarted = AsyncStream<Void>.makeStream()
        let secondFinished = AsyncStream<Void>.makeStream()
        var firstContinuation: CheckedContinuation<Void, Never>?
        var secondContinuation: CheckedContinuation<Void, Never>?
        var secondWasCancelled = false
        var firstStartedIterator = firstStarted.stream.makeAsyncIterator()
        var firstFinishedIterator = firstFinished.stream.makeAsyncIterator()
        var secondStartedIterator = secondStarted.stream.makeAsyncIterator()
        var secondFinishedIterator = secondFinished.stream.makeAsyncIterator()
        resources.startScreenshotOperation {
            await withCheckedContinuation {
                firstContinuation = $0
                firstStarted.continuation.yield(())
            }
            firstFinished.continuation.yield(())
        }
        _ = await firstStartedIterator.next()
        resources.startScreenshotOperation {
            await withCheckedContinuation {
                secondContinuation = $0
                secondStarted.continuation.yield(())
            }
            secondWasCancelled = Task.isCancelled
            secondFinished.continuation.yield(())
        }
        _ = await secondStartedIterator.next()

        // Act
        firstContinuation?.resume()
        _ = await firstFinishedIterator.next()
        resources.cancelTasks()
        secondContinuation?.resume()
        _ = await secondFinishedIterator.next()

        // Assert
        #expect(secondWasCancelled)
    }

    @Test func cancelledScreenshotDiscardsLateCaptureResult() async {
        // Arrange
        let resources = DenWindowResources()
        let started = AsyncStream<Void>.makeStream()
        let finished = AsyncStream<Void>.makeStream()
        var startedIterator = started.stream.makeAsyncIterator()
        var finishedIterator = finished.stream.makeAsyncIterator()
        var continuation: CheckedContinuation<Void, Never>?
        var outputProduced = false
        resources.startScreenshotOperation {
            defer { finished.continuation.yield(()) }
            await withCheckedContinuation {
                continuation = $0
                started.continuation.yield(())
            }
            guard !Task.isCancelled else { return }
            outputProduced = true
        }
        _ = await startedIterator.next()

        // Act
        resources.cancelTasks()
        continuation?.resume()
        _ = await finishedIterator.next()

        // Assert
        #expect(!outputProduced)
    }
}
