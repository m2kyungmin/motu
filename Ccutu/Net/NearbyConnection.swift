import Foundation
import Network
import Security
import CryptoKit
import KkutuCore

/// 방 코드는 Bonjour로 광고하지 않는다. 같은 코드를 입력한 기기만 TLS 연결을 맺는다.
enum NearbySecurity {
    static let serviceType = "_motu-v2._tcp"

    static func parameters(code: String) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let key = Data(HMAC<SHA256>.authenticationCode(for: Data("motu-nearby-v2".utf8),
            using: SymmetricKey(data: Data(code.utf8))))
        let identity = Data("motu-nearby-v2".utf8)
        key.withUnsafeBytes { keyBytes in
            identity.withUnsafeBytes { identityBytes in
                sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions,
                    DispatchData(bytes: keyBytes) as __DispatchData,
                    DispatchData(bytes: identityBytes) as __DispatchData)
            }
        }
        // Apple의 TicTacToe 샘플과 같은 PSK 전용 암호군. 인증서 예외 처리를 두지 않는다.
        sec_protocol_options_append_tls_ciphersuite(tls.securityProtocolOptions,
            tls_ciphersuite_t(rawValue: TLS_PSK_WITH_AES_128_GCM_SHA256)!)
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.connectionTimeout = 10
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 2
        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }
}

/// 메인 큐에서 수신·종료를 순서대로 처리한다. 경주 프레임은 대기 중 최신 하나만 남긴다.
@MainActor final class NearbyConnection {
    let connection: NWConnection
    var onReady: () -> Void = {}
    var onPacket: (Data) -> Void = { _ in }
    var onClosed: () -> Void = {}
    private var decoder = NetworkPacketDecoder()
    private var reliable: [Data] = []
    private var latestFrame: Data?
    private var sending = false
    private var ready = false
    private var closed = false

    init(_ connection: NWConnection) { self.connection = connection }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, !self.closed else { return }
                switch state {
                case .ready:
                    self.ready = true
                    self.onReady()
                    self.receive()
                    self.flush()
                case .failed, .cancelled: self.close()
                default: break
                }
            }
        }
        connection.start(queue: .main)
    }

    func send(_ data: Data, transient: Bool = false) {
        guard !closed, let packet = try? NetworkPacketDecoder.encode(data) else { return }
        if transient { latestFrame = packet }
        else {
            guard reliable.count < 128 else { close(); return }
            reliable.append(packet)
        }
        flush()
    }

    func close(notify: Bool = true) {
        guard !closed else { return }
        closed = true
        connection.stateUpdateHandler = nil
        connection.cancel()
        reliable.removeAll(); latestFrame = nil
        if notify { onClosed() }
    }

    private func flush() {
        guard ready, !sending, !closed else { return }
        let packet: Data
        if !reliable.isEmpty { packet = reliable.removeFirst() }
        else if let frame = latestFrame { packet = frame; latestFrame = nil }
        else { return }
        sending = true
        connection.send(content: packet, completion: .contentProcessed { [weak self] error in
            Task { @MainActor in
                guard let self, !self.closed else { return }
                self.sending = false
                if error != nil { self.close() } else { self.flush() }
            }
        })
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, !self.closed else { return }
                if let data {
                    do {
                        for packet in try self.decoder.append(data) {
                            guard !self.closed else { return }
                            self.onPacket(packet)
                        }
                    } catch { self.close(); return }
                }
                if complete || error != nil { self.close() } else { self.receive() }
            }
        }
    }
}
