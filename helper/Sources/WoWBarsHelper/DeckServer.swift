import DeckKit
import Foundation
import Network

/// Local WebSocket server the Stream Deck plugin connects to (docs/deck-protocol.md).
/// Listens on the loopback interface only.
final class DeckServer {
    /// Called on the main queue when the plugin reports a key press.
    var onPress: ((Int) -> Void)?
    /// Called on the main queue with the number of connected plugins.
    var onClientsChanged: ((Int) -> Void)?

    private let port: UInt16
    private let queue = DispatchQueue(label: "WoWBarsHelper.deck")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var images: [Int: String] = [:]  // latest image per slot

    init(port: UInt16 = DeckMessage.defaultPort) {
        self.port = port
    }

    func start() {
        queue.async { self.listen() }
    }

    /// Sets a slot's image and sends it to every connected plugin.
    func update(slot: Int, image: String) {
        queue.async {
            self.images[slot] = image
            let message = DeckMessage.slot(slot: slot, image: image)
            for c in self.connections.values { self.send(message, on: c) }
        }
    }

    // MARK: Queue-confined

    private func listen() {
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        let params = NWParameters.tcp
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!)
        do {
            let l = try NWListener(using: params)
            l.newConnectionHandler = { [weak self] in self?.accept($0) }
            l.stateUpdateHandler = { [weak self] state in
                if case .failed = state { self?.retry() }
            }
            l.start(queue: queue)
            listener = l
        } catch {
            retry()
        }
    }

    private func retry() {
        listener?.cancel()
        listener = nil
        queue.asyncAfter(deadline: .now() + 2) { self.listen() }
    }

    private func accept(_ c: NWConnection) {
        let id = ObjectIdentifier(c)
        connections[id] = c
        c.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.send(.hello(version: DeckMessage.protocolVersion), on: c)
                for (slot, image) in self.images.sorted(by: { $0.key < $1.key }) {
                    self.send(.slot(slot: slot, image: image), on: c)
                }
                self.reportClients()
            case .failed, .cancelled:
                self.connections[id] = nil
                self.reportClients()
            default:
                break
            }
        }
        c.start(queue: queue)
        receive(on: c)
    }

    private func receive(on c: NWConnection) {
        c.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, case .press(let slot) = DeckMessage.decode(data) {
                DispatchQueue.main.async { self.onPress?(slot) }
            }
            if error == nil {
                self.receive(on: c)
            } else {
                c.cancel()
            }
        }
    }

    private func send(_ message: DeckMessage, on c: NWConnection) {
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "message", metadata: [meta])
        c.send(content: message.encoded(), contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
    }

    private func reportClients() {
        let n = connections.values.filter { $0.state == .ready }.count
        DispatchQueue.main.async { self.onClientsChanged?(n) }
    }
}
