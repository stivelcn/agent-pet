import Foundation
import Testing

/// A bounded rendezvous for callback/socket tests; assertions use Swift Testing directly.
final class TestSignal: Sendable {
    let description: String
    private let semaphore = DispatchSemaphore(value: 0)
    init(description: String) { self.description = description }
    func fulfill() { semaphore.signal() }
    func wait(until deadline: DispatchTime) -> Bool { semaphore.wait(timeout: deadline) == .success }
}

func waitForSignals(_ signals: [TestSignal], timeout: TimeInterval,
                    sourceLocation: SourceLocation = #_sourceLocation) {
    let deadline = DispatchTime.now() + timeout
    for signal in signals {
        #expect(signal.wait(until: deadline), Comment(rawValue: signal.description), sourceLocation: sourceLocation)
    }
}
