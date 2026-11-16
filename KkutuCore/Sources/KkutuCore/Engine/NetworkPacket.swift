import Foundation

/// TCP는 메시지 경계를 보존하지 않는다. 길이 헤더를 먼저 검사한 뒤 한 패킷씩 꺼낸다.
public struct NetworkPacketDecoder {
    public static let maximumSize = 1_048_576
    public enum PacketError: Error { case invalidSize }
    private var buffer = Data()

    public init() {}

    public static func encode(_ payload: Data) throws -> Data {
        guard !payload.isEmpty, payload.count <= maximumSize else { throw PacketError.invalidSize }
        let size = UInt32(payload.count)
        return Data([UInt8(size >> 24), UInt8((size >> 16) & 255), UInt8((size >> 8) & 255), UInt8(size & 255)]) + payload
    }

    public mutating func append(_ bytes: Data) throws -> [Data] {
        buffer.append(bytes)
        var packets: [Data] = []
        while buffer.count >= 4 {
            let size = buffer.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
            guard size > 0, size <= Self.maximumSize else {
                buffer.removeAll()
                throw PacketError.invalidSize
            }
            guard buffer.count >= size + 4 else { break }
            packets.append(Data(buffer.dropFirst(4).prefix(size)))
            buffer = Data(buffer.dropFirst(size + 4))
        }
        return packets
    }
}
