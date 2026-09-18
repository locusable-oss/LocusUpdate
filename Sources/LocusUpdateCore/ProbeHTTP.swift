import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum ProbeHTTP {
    /// Shared fetch so Linux (FoundationNetworking) and macOS use one path.
    /// Returns nil on transport failure. Callers still bound status codes and body size.
    static func data(for request: URLRequest, session: URLSession) async -> (Data, URLResponse)? {
        await withCheckedContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, _ in
                if let data, let response {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(returning: nil)
                }
            }
            task.resume()
        }
    }
}
