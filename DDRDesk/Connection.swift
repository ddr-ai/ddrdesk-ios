import Foundation
import Network
import Combine
import UIKit
import CommonCrypto

enum ConnState: Equatable {
    case idle
    case searching
    case connecting(String)
    case authenticating
    case streaming
    case reconnecting(String)
    case failed(String)
}

@MainActor
final class DeskSession: ObservableObject {
    @Published var state: ConnState = .idle
    @Published var statusLine: String = ""
    @Published var hostName: String = ""
    @Published var screenW: UInt32 = 1280
    @Published var screenH: UInt32 = 800

    let video = VideoSink()
    let discovery = Discovery()

    private var connection: NWConnection?
    private var recvBuffer = Data()
    private var connectionID = ""
    private var sessionToken: String?
    private var backoff: TimeInterval = 0.5
    private var reconnectTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var shouldRun = false
    private var lastViewport: ViewportMsg?
    private var rttMs: Int = 0
    private var kbps: UInt32 = 8000

    func connect(id raw: String) {
        let id = raw.filter(\.isNumber)
        guard id.count == 9 else {
            state = .failed("Enter the 9-digit connection ID")
            return
        }
        connectionID = id
        shouldRun = true
        backoff = 0.5
        discovery.start()
        attempt()
    }

    func disconnect() {
        shouldRun = false
        reconnectTask?.cancel()
        pingTask?.cancel()
        discovery.stop()
        send(type: .goodbye, payload: Data("bye".utf8))
        connection?.cancel()
        connection = nil
        video.reset()
        state = .idle
        statusLine = ""
    }

    func sendViewport() {
        let m = ScreenMetrics.current()
        let vp = ViewportMsg(
            w: m.pixelsW, h: m.pixelsH,
            points_w: m.pointsW, points_h: m.pointsH,
            scale: m.scale, orientation: m.orientation
        )
        lastViewport = vp
        if let data = try? JSONEncoder().encode(vp) {
            send(type: .viewport, payload: data)
        }
    }

    func sendInput(_ payload: Data) {
        send(type: .input, payload: payload)
    }

    func requestKeyframe() {
        send(type: .requestKeyframe, payload: Data())
    }

    private func attempt() {
        guard shouldRun else { return }
        state = .searching
        statusLine = "Looking for host \(prettyID)…"

        var candidates: [NWEndpoint] = discovery.endpoints(for: connectionID)
        candidates.append(contentsOf: discovery.endpoints(for: "_unknown"))

        if let saved = PairingStore.shared.pairing(for: connectionID) {
            for ep in saved.endpoints {
                if let nw = parseEndpoint(ep) {
                    candidates.append(nw)
                }
            }
        }

        // Last-ditch: if the ID field was never paired and mDNS is empty,
        // keep retrying — mDNS often appears a second later.
        if candidates.isEmpty {
            state = .reconnecting("Searching for \(prettyID)")
            scheduleReconnect()
            return
        }

        // Dedup by description
        var seen = Set<String>()
        let unique = candidates.filter { seen.insert($0.debugDescription).inserted }
        tryNext(unique, index: 0)
    }

    private func tryNext(_ list: [NWEndpoint], index: Int) {
        guard shouldRun else { return }
        guard index < list.count else {
            state = .reconnecting("No reachable endpoint")
            scheduleReconnect()
            return
        }
        let ep = list[index]
        state = .connecting(String(describing: ep))
        statusLine = "Connecting…"
        let conn = makeTLSConnection(to: ep)
        connection = conn
        conn.stateUpdateHandler = { [weak self] st in
            Task { @MainActor in
                guard let self else { return }
                switch st {
                case .ready:
                    self.state = .authenticating
                    self.statusLine = "Authenticating…"
                    self.startReceive()
                    self.sendHello()
                case .failed(let err):
                    self.statusLine = err.localizedDescription
                    self.connection = nil
                    self.tryNext(list, index: index + 1)
                case .waiting(let err):
                    self.statusLine = err.localizedDescription
                case .cancelled:
                    break
                default:
                    break
                }
            }
        }
        conn.start(queue: .global(qos: .userInteractive))
    }

    private func makeTLSConnection(to endpoint: NWEndpoint) -> NWConnection {
        let tls = NWProtocolTLS.Options()
        let sec = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv13)
        sec_protocol_options_set_max_tls_protocol_version(sec, .TLSv13)
        sec_protocol_options_add_tls_application_protocol(sec, "ddrdesk/1")
        let expectedFP = PairingStore.shared.pairing(for: connectionID)?.fingerprint
        sec_protocol_options_set_verify_block(sec, { _, trust, complete in
            // TOFU: accept the self-signed host cert. After pairing we pin SHA-256.
            if let expectedFP, !expectedFP.isEmpty {
                let t = sec_trust_copy_ref(trust).takeRetainedValue()
                if let cert = (SecTrustCopyCertificateChain(t) as? [SecCertificate])?.first {
                    let fp = sha256Hex(cert)
                    complete(expectedFP.hasSuffix(fp) || expectedFP.contains(fp))
                    return
                }
            }
            complete(true)
        }, .main)

        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 5
        tcp.connectionTimeout = 8

        let params = NWParameters(tls: tls, tcp: tcp)
        params.expiredDNSBehavior = .allow
        params.serviceClass = .responsiveData
        params.includePeerToPeer = true
        return NWConnection(to: endpoint, using: params)
    }

    private func sendHello() {
        let m = ScreenMetrics.current()
        let hello = ClientHello(
            id: connectionID,
            device: UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone",
            w: m.pixelsW, h: m.pixelsH,
            points_w: m.pointsW, points_h: m.pointsH,
            scale: m.scale,
            orientation: m.orientation,
            proto: 1,
            session: sessionToken
        )
        if let data = try? FrameCodec.encodeJSON(type: .clientHello, value: hello) {
            sendRaw(data)
        }
    }

    private func startReceive() {
        recvBuffer.removeAll(keepingCapacity: true)
        receiveMore()
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run { self?.sendPing() }
            }
        }
    }

    private func receiveMore() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                if let data, !data.isEmpty {
                    self.recvBuffer.append(data)
                    self.drainFrames()
                }
                if isComplete || error != nil {
                    self.handleDrop(error?.localizedDescription ?? "connection closed")
                    return
                }
                self.receiveMore()
            }
        }
    }

    private func drainFrames() {
        while recvBuffer.count >= 4 {
            let len: UInt32 = recvBuffer.prefix(4).withUnsafeBytes { raw in
                var v: UInt32 = 0
                Swift.withUnsafeMutableBytes(of: &v) { dest in
                    dest.copyBytes(from: raw.prefix(4))
                }
                return UInt32(bigEndian: v)
            }
            if len == 0 || len > UInt32(FrameCodec.maxFrame) {
                handleDrop("invalid frame")
                return
            }
            let total = 4 + Int(len)
            guard recvBuffer.count >= total else { return }
            let body = recvBuffer.subdata(in: 4..<total)
            recvBuffer.removeSubrange(0..<total)
            let type = Msg(rawValue: body[0])
            let payload = body.dropFirst()
            handle(type: type, payload: Data(payload))
        }
    }

    private func handle(type: Msg?, payload: Data) {
        switch type {
        case .serverHello:
            if let hello = try? JSONDecoder().decode(ServerHello.self, from: payload) {
                hostName = hello.name
                screenW = hello.screen_w
                screenH = hello.screen_h
                sessionToken = hello.session
                PairingStore.shared.rememberEndpoints(
                    id: connectionID, name: hello.name,
                    fp: hello.fp, endpoints: hello.endpoints
                )
                state = .streaming
                statusLine = "Connected to \(hello.name)"
                backoff = 0.5
                send(type: .requestKeyframe, payload: Data())
            }
        case .authFail:
            let err = (try? JSONDecoder().decode(AuthFail.self, from: payload))?.error ?? "auth failed"
            shouldRun = false
            state = .failed(err == "bad_id" ? "Wrong connection ID" : err)
            connection?.cancel()
        case .video:
            guard payload.count >= 9 else { return }
            let flags = payload[0]
            let nal = payload.subdata(in: 9..<payload.count)
            video.submit(annexB: nal, keyframe: (flags & 1) == 1)
        case .status:
            if let s = try? JSONDecoder().decode(StatusMsg.self, from: payload) {
                statusLine = s.msg.isEmpty ? s.state : s.msg
            }
        case .cursor:
            if let c = try? JSONDecoder().decode(CursorPos.self, from: payload) {
                cursor = c
            }
        case .pong:
            if payload.count >= 8 {
                let sent = payload.prefix(8).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).bigEndian }
                let now = DispatchTime.now().uptimeNanoseconds / 1_000
                rttMs = Int(max(0, Int64(now) - Int64(sent)) / 1_000)
                adaptBitrate()
            }
        default:
            break
        }
    }

    private func adaptBitrate() {
        // Bitrate is advisory only; restarting the encoder froze the picture.
        _ = rttMs
        _ = kbps
    }

    private func sendPing() {
        var ts = (DispatchTime.now().uptimeNanoseconds / 1_000).bigEndian
        send(type: .ping, payload: Data(bytes: &ts, count: 8))
    }

    private func handleDrop(_ reason: String) {
        connection?.cancel()
        connection = nil
        pingTask?.cancel()
        guard shouldRun else { return }
        state = .reconnecting(reason)
        statusLine = "Disconnected — retrying…"
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        let wait = backoff
        backoff = min(backoff * 2, 10)
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            await MainActor.run { self?.attempt() }
        }
    }

    private func send(type: Msg, payload: Data) {
        sendRaw(FrameCodec.encode(type: type, payload: payload))
    }

    private func sendRaw(_ data: Data) {
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }

    var prettyID: String {
        let id = connectionID
        guard id.count == 9 else { return id }
        let a = id.index(id.startIndex, offsetBy: 3)
        let b = id.index(id.startIndex, offsetBy: 6)
        return "\(id[..<a]) \(id[a..<b]) \(id[b...])"
    }
}

func parseEndpoint(_ s: String) -> NWEndpoint? {
    // "[v6]:port" or "host:port"
    if s.hasPrefix("["), let rb = s.firstIndex(of: "]") {
        let host = String(s[s.index(after: s.startIndex)..<rb])
        let rest = s[s.index(after: rb)...]
        let portStr = rest.hasPrefix(":") ? String(rest.dropFirst()) : "44789"
        guard let port = NWEndpoint.Port(portStr) else { return nil }
        return .hostPort(host: .ipv6(IPv6Address(host) ?? IPv6Address("::1")!), port: port)
    }
    let parts = s.split(separator: ":")
    guard parts.count == 2, let port = NWEndpoint.Port(String(parts[1])) else { return nil }
    let host = String(parts[0])
    if let v4 = IPv4Address(host) {
        return .hostPort(host: .ipv4(v4), port: port)
    }
    return .hostPort(host: .name(host, nil), port: port)
}

func sha256Hex(_ cert: SecCertificate) -> String {
    let data = SecCertificateCopyData(cert) as Data
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes { ptr in
        _ = CC_SHA256(ptr.baseAddress, CC_LONG(data.count), &hash)
    }
    return hash.map { String(format: "%02x", $0) }.joined()
}
