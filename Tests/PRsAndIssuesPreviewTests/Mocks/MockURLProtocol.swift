import Foundation

/// A mock URL protocol for testing network requests without making actual network calls.
/// Register request handlers to return mock responses for specific URLs.
///
/// Usage:
/// ```swift
/// MockURLProtocol.requestHandler = { request in
///     let response = HTTPURLResponse(url: request.url!, statusCode: 200, ...)
///     let data = "{ \"key\": \"value\" }".data(using: .utf8)!
///     return (response, data)
/// }
/// let session = URLSession(configuration: MockURLProtocol.mockConfiguration)
/// ```
final class MockURLProtocol: URLProtocol, @unchecked Sendable {

    // MARK: - Static Properties

    /// Handler that processes requests and returns mock responses.
    /// Set this before making requests to control what data is returned.
    static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    /// Recorded requests for verification in tests
    private static var _recordedRequests: [URLRequest] = []
    private static let lock = NSLock()

    static var recordedRequests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _recordedRequests
    }

    /// Clear recorded requests between tests
    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        _recordedRequests.removeAll()
        requestHandler = nil
    }

    /// A URLSession configuration that uses MockURLProtocol
    static var mockConfiguration: URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        return config
    }

    /// Create a URLSession that uses mock responses
    static func mockSession() -> URLSession {
        URLSession(configuration: mockConfiguration)
    }

    // MARK: - URLProtocol Overrides

    override class func canInit(with request: URLRequest) -> Bool {
        // Handle all requests
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        // Record the request for verification
        Self.lock.lock()
        Self._recordedRequests.append(request)
        Self.lock.unlock()

        guard let handler = Self.requestHandler else {
            let error = NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorUnknown,
                userInfo: [NSLocalizedDescriptionKey: "No request handler set in MockURLProtocol"]
            )
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        // No-op for mock
    }
}

// MARK: - Helper Extensions

extension MockURLProtocol {

    /// Create a success response with JSON data
    static func successResponse(
        for request: URLRequest,
        jsonString: String,
        statusCode: Int = 200
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        let data = jsonString.data(using: .utf8)!
        return (response, data)
    }

    /// Create a success response with JSON data and Link header for pagination
    static func successResponse(
        for request: URLRequest,
        jsonString: String,
        statusCode: Int = 200,
        linkHeader: String?
    ) -> (HTTPURLResponse, Data) {
        var headers = ["Content-Type": "application/json"]
        if let link = linkHeader {
            headers["Link"] = link
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        let data = jsonString.data(using: .utf8)!
        return (response, data)
    }

    /// Create an error response
    static func errorResponse(
        for request: URLRequest,
        statusCode: Int,
        message: String
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        let errorJson = """
        {"message": "\(message)", "documentation_url": "https://docs.github.com"}
        """
        let data = errorJson.data(using: .utf8)!
        return (response, data)
    }

    /// Create a network error
    static func networkError(code: Int = NSURLErrorNotConnectedToInternet) -> Error {
        NSError(
            domain: NSURLErrorDomain,
            code: code,
            userInfo: [NSLocalizedDescriptionKey: "Network error"]
        )
    }
}
