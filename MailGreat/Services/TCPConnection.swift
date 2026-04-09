import Foundation
import Network

/// A lightweight async/await wrapper around NWConnection for TCP + TLS.
final class TCPConnection: @unchecked Sendable {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.mailgreat.tcp", qos: .utility)
    private let host: String
    private let port: UInt16
    private let useTLS: Bool

    init(host: String, port: UInt16, useTLS: Bool) {
        self.host = host
        self.port = port
        self.useTLS = useTLS
    }

    /// Establish the TCP connection (with optional TLS).
    func start() async throws {
        let parameters: NWParameters
        if useTLS {
            let tlsOptions = NWProtocolTLS.Options()
            parameters = NWParameters(tls: tlsOptions, tcp: .init())
        } else {
            parameters = .tcp
        }

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw EmailServiceError.connectionFailed("Invalid port: \(port)")
        }

        let conn = NWConnection(
            host: NWEndpoint.Host(host),
            port: nwPort,
            using: parameters
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            conn.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    continuation.resume()
                case .failed(let error):
                    resumed = true
                    continuation.resume(throwing: EmailServiceError.connectionFailed(error.localizedDescription))
                case .cancelled:
                    resumed = true
                    continuation.resume(throwing: EmailServiceError.connectionClosed)
                default:
                    break
                }
            }
            conn.start(queue: self.queue)
        }

        self.connection = conn
    }

    /// Send data over the connection.
    func send(_ data: Data) async throws {
        guard let connection else { throw EmailServiceError.notConnected }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: EmailServiceError.connectionFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    /// Send a string (UTF-8 encoded) over the connection.
    func sendString(_ string: String) async throws {
        guard let data = string.data(using: .utf8) else {
            throw EmailServiceError.commandFailed("Failed to encode string")
        }
        try await send(data)
    }

    /// Receive data from the connection.
    func receive(minimumLength: Int = 1, maximumLength: Int = 65536) async throws -> Data {
        guard let connection else { throw EmailServiceError.notConnected }

        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(
                minimumIncompleteLength: minimumLength,
                maximumLength: maximumLength
            ) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: EmailServiceError.connectionFailed(error.localizedDescription))
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: EmailServiceError.connectionClosed)
                } else {
                    continuation.resume(throwing: EmailServiceError.connectionClosed)
                }
            }
        }
    }

    /// Read exactly the specified number of bytes.
    func receiveExact(_ count: Int) async throws -> Data {
        var accumulated = Data()
        while accumulated.count < count {
            let remaining = count - accumulated.count
            let chunk = try await receive(minimumLength: 1, maximumLength: remaining)
            accumulated.append(chunk)
        }
        return accumulated
    }

    /// Close the connection.
    func cancel() {
        connection?.cancel()
        connection = nil
    }
}
