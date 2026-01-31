import Foundation

/// Thread-safe wrapper for mutable state captured in @Sendable closures.
/// Used in tests where MockURLProtocol's requestHandler requires Sendable closures.
///
/// Swift 6's strict concurrency checking prevents mutation of captured variables
/// in `@Sendable` closures. This wrapper provides thread-safe access to mutable state.
///
/// Usage:
/// ```swift
/// let counter = SendableBox(0)
/// MockURLProtocol.requestHandler = { request in
///     counter.value += 1  // Thread-safe mutation
///     return mockResponse()
/// }
/// XCTAssertEqual(counter.value, 1)
/// ```
final class SendableBox<T>: @unchecked Sendable {
    private var _value: T
    private let lock = NSLock()

    init(_ value: T) {
        self._value = value
    }

    var value: T {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _value = newValue
        }
    }

    /// Atomically modify the value using a closure
    func modify(_ transform: (inout T) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        transform(&_value)
    }
}
