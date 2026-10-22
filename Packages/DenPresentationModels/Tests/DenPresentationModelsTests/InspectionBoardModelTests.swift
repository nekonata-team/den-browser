import DenDomain
import DenPresentationModels
import Foundation
import Testing

@MainActor
struct InspectionBoardModelTests {
    @Test(arguments: [false, true])
    func lateChildrenDoNotUpdateAfterCancellationOrNavigation(navigated: Bool) async throws {
        // Arrange
        let node = try JSONDecoder().decode(
            InspectionDOMNode.self,
            from: Data(#"{"id":"root","tag":"div","attributes":[],"text":"","childCount":1}"#.utf8))
        var pending: CheckedContinuation<[InspectionDOMNode], Never>?
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let (finished, finishedContinuation) = AsyncStream<Void>.makeStream()
        let model = InspectionBoardModel(
            runtimeID: UUID(), targetBoard: { nil }, pageGeneration: { 0 }, hasPage: { true }, isActive: { true },
            startCollection: { _ in }, setHighlightColor: { _ in }, beginPicking: { _ in }, selectNode: { _ in },
            highlightNode: { _ in },
            readSnapshot: { .empty },
            readChildren: { _ in
                let result = await withCheckedContinuation { continuation in
                    pending = continuation
                    startedContinuation.yield(())
                    startedContinuation.finish()
                }
                // Queue the assertion after the Model's synchronous publication opportunity.
                Task { @MainActor in
                    finishedContinuation.yield(())
                    finishedContinuation.finish()
                }
                return result
            }, refreshChildren: { _ in [:] })
        model.toggleDOMNode(node)
        var startedIterator = started.makeAsyncIterator()
        _ = await startedIterator.next()

        // Act
        if navigated { model.generationChanged(1) } else { model.cancelLoading() }
        pending?.resume(returning: [node])
        var finishedIterator = finished.makeAsyncIterator()
        _ = await finishedIterator.next()

        // Assert
        #expect(model.loadedChildren.isEmpty)
        #expect(model.loadingNodeIDs.isEmpty)
    }
}
