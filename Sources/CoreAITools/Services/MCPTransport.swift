import Foundation
import Network

// MARK: - MCP Transport Protocol

protocol MCPTransport: AnyObject {
    func send(_ data: Data) async throws
    func receive() async throws -> Data?
    func close()
}

// MARK: - Stdio Transport

final class MCPStdioTransport: MCPTransport {
    private let inputPipe: Pipe
    private let outputPipe: Pipe

    init(inputPipe: Pipe, outputPipe: Pipe) {
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe
    }

    func send(_ data: Data) async throws {
        inputPipe.fileHandleForWriting.write(data + "\n".data(using: .utf8)!)
    }

    func receive() async throws -> Data? {
        let data = outputPipe.fileHandleForReading.availableData
        guard !data.isEmpty else { return nil }
        return data
    }

    func close() {
        inputPipe.fileHandleForWriting.closeFile()
        outputPipe.fileHandleForReading.closeFile()
    }
}

// MARK: - WebSocket Transport


final class MCPWebSocketTransport: MCPTransport {
    private var webSocket: URLSessionWebSocketTask?
    private let url: URL
    private var session: URLSession

    init(url: URL) {
        self.url = url
        self.session = URLSession(configuration: .default)
    }

    func connect() async throws {
        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()
    }

    func send(_ data: Data) async throws {
        try await webSocket?.send(.data(data))
    }

    func receive() async throws -> Data? {
        guard let msg = try await webSocket?.receive() else { return nil }
        switch msg {
        case .data(let data): return data
        case .string(let str): return str.data(using: .utf8)
        @unknown default: return nil
        }
    }

    func close() {
        webSocket?.cancel(with: .goingAway, reason: nil)
    }
}

// MARK: - Local Socket Transport (Unix Domain Socket)


final class MCPLocalSocketTransport: MCPTransport {
    private var connection: NWConnection?
    private let socketPath: String

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    func connect() async throws {
        let endpoint = NWEndpoint.unix(path: socketPath)
        let params = NWParameters.tcp
        connection = NWConnection(to: endpoint, using: params)
        connection?.start(queue: .global())
    }

    func send(_ data: Data) {
        guard let connection = connection else { return }
        connection.send(content: data + "\n".data(using: .utf8)!, completion: .contentProcessed { _ in })
    }

    func receive() async throws -> Data? {
        guard let connection = connection else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
    }

    func close() {
        connection?.cancel()
    }
}

// MARK: - Transport Factory

enum MCPTransportFactory {
    static func create(for config: MCPServerConfig) async throws -> MCPTransport {
        if config.command.hasPrefix("ws://") || config.command.hasPrefix("wss://") {
            let transport = MCPWebSocketTransport(url: URL(string: config.command)!)
            try await transport.connect()
            return transport
        } else if config.command.hasPrefix("unix://") {
            let path = String(config.command.dropFirst("unix://".count))
            let transport = MCPLocalSocketTransport(socketPath: path)
            try await transport.connect()
            return transport
        } else {
            // Default: stdio (process-based)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: config.command)
            process.arguments = config.args

            var env = ProcessInfo.processInfo.environment
            if let extra = config.env { env.merge(extra) { _, new in new } }
            process.environment = env

            let inputPipe = Pipe()
            let outputPipe = Pipe()
            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = Pipe()

            try process.run()
            return MCPStdioTransport(inputPipe: inputPipe, outputPipe: outputPipe)
        }
    }
}
