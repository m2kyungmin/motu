import Foundation
import Testing
@testable import KkutuCore

struct NetworkPacketTests {
    @Test func splitHeaderAndPayload() throws {
        let payload = Data("한글 단어".utf8)
        let packet = try NetworkPacketDecoder.encode(payload)
        var decoder = NetworkPacketDecoder()
        for byte in packet.dropLast() { #expect(try decoder.append(Data([byte])).isEmpty) }
        #expect(try decoder.append(Data([packet.last!])) == [payload])
    }

    @Test func coalescedPacketsAndPartialTail() throws {
        let a = try NetworkPacketDecoder.encode(Data([1, 2, 3]))
        let b = try NetworkPacketDecoder.encode(Data([4, 5]))
        var decoder = NetworkPacketDecoder()
        #expect(try decoder.append(a + b.prefix(5)) == [Data([1, 2, 3])])
        #expect(try decoder.append(Data(b.suffix(1))) == [Data([4, 5])])
    }

    @Test func rejectsInvalidLengthBeforeAllocatingPayload() throws {
        for header in [Data([0, 0, 0, 0]), Data([255, 255, 255, 255]), Data([0, 16, 0, 1])] {
            var decoder = NetworkPacketDecoder()
            #expect(throws: NetworkPacketDecoder.PacketError.self) { try decoder.append(header) }
            #expect(try decoder.append(NetworkPacketDecoder.encode(Data([7]))) == [Data([7])])
        }
        #expect(throws: NetworkPacketDecoder.PacketError.self) { try NetworkPacketDecoder.encode(Data()) }
        #expect(throws: NetworkPacketDecoder.PacketError.self) {
            try NetworkPacketDecoder.encode(Data(count: NetworkPacketDecoder.maximumSize + 1))
        }
    }
}
