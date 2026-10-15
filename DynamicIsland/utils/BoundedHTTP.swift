import Foundation

enum BoundedHTTP {
    /// Bound both elapsed time and received bytes, including chunked responses.
    /// AsyncBytes.task is cancelled on every exit (size rejection, timeout, or caller cancellation).
    static func data(from url: URL, session: URLSession = .shared,
                     limit: Int = 2 * 1024 * 1024, timeout: TimeInterval = 15) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        let (bytes, response) = try await session.bytes(for: request)
        let deadline = Task {
            do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
            bytes.task.cancel()
        }
        defer { deadline.cancel(); bytes.task.cancel() }
        guard response.expectedContentLength <= Int64(limit) else { throw URLError(.dataLengthExceedsMaximum) }
        return try await withTaskCancellationHandler {
            var data = Data()
            for try await byte in bytes {
                guard data.count < limit else { throw URLError(.dataLengthExceedsMaximum) }
                data.append(byte)
            }
            try Task.checkCancellation()
            return (data, response)
        } onCancel: { bytes.task.cancel() }
    }
}
