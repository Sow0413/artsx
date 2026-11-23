import XCTest
@testable import SurveyCore

/// 偽の caster。GGA が無い、User-Agent が NTRIP で始まらない、認証が違う、をそれぞれ拒否する。
private struct FakeCaster {
    var user = "docomo-id"
    var password = "secret-pass"
    var mount = "RRSGD2024"

    func respond(to wire: Data) -> Data {
        let text = String(decoding: wire, as: UTF8.self)
        if text.contains("GET / HTTP/") {
            return Data("SOURCETABLE 200 OK\r\n\r\nSTR;RRSGD2024;d-gnss.jp;2101\r\nSTR;RRSGD;d-gnss.jp;2101\r\nENDSOURCETABLE\r\n".utf8)
        }
        guard text.contains("User-Agent: NTRIP ") else {
            return Data("HTTP/1.1 503 Service Unavailable\r\n\r\n".utf8)
        }
        let token = NTRIPExchange.basicToken(user: user, password: password)
        guard text.contains("Authorization: Basic \(token)") else {
            return Data("HTTP/1.1 401 Unauthorized\r\n\r\n".utf8)
        }
        guard text.contains("GET /\(mount) ") else {
            return Data("HTTP/1.1 404 Not Found\r\n\r\n".utf8)
        }
        guard text.contains("$GPGGA,") || text.contains("$GNGGA,") else {
            return Data("HTTP/1.1 503 Service Unavailable\r\n\r\n".utf8)
        }
        return Data("ICY 200 OK\r\n\r\n".utf8) + Data([0xD3, 0x00, 0x13])
    }
}

final class NTRIPTests: XCTestCase {
    func testRequestUsesEditedMountAndMasksThePassword() {
        let gga = NTRIPExchange.gpgga(latitudeDegrees: 35.1156, longitudeDegrees: 136.9021, ellipsoidalHeightMeters: 40, at: Date(timeIntervalSince1970: 1_700_000_000))
        let wire = NTRIPExchange.request(
            host: "d-gnss.jp",
            mount: "RRSGD2024",
            user: "docomo-id",
            password: "secret-pass",
            dialect: .v1,
            gga: gga
        )
        let text = String(decoding: wire.bytes, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("GET /RRSGD2024 HTTP/1.0\r\n"))
        XCTAssertTrue(text.contains("User-Agent: NTRIP artsx/1.1\r\n"))
        XCTAssertTrue(text.contains("Authorization: Basic \(NTRIPExchange.basicToken(user: "docomo-id", password: "secret-pass"))\r\n"))
        XCTAssertTrue(text.contains("\r\n\r\n$GPGGA,"))
        XCTAssertFalse(text.contains("RRSGD HTTP"))
        XCTAssertFalse(wire.log.contains("secret-pass"))
        XCTAssertTrue(wire.log.contains("Authorization: Basic ***"))
        XCTAssertTrue(wire.log.contains("$GPGGA,"))
    }

    func testVersionTwoHeaders() {
        let wire = NTRIPExchange.request(host: "d-gnss.jp", mount: "RRSG2024", user: "id", password: "pw", dialect: .v2, gga: nil)
        let text = String(decoding: wire.bytes, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("GET /RRSG2024 HTTP/1.1\r\n"))
        XCTAssertTrue(text.contains("Ntrip-Version: Ntrip/2.0\r\n"))
        XCTAssertTrue(text.contains("Host: d-gnss.jp\r\n"))
        XCTAssertFalse(text.hasPrefix("NTRIP"))
        XCTAssertTrue(text.contains("User-Agent: NTRIP artsx/1.1"))
    }

    func testFakeCasterRequiresGGAUserAgentAndAuth() {
        let caster = FakeCaster()
        let gga = NTRIPExchange.gpgga(latitudeDegrees: 35.1156, longitudeDegrees: 136.9021, ellipsoidalHeightMeters: nil, at: Date(timeIntervalSince1970: 0))
        let good = NTRIPExchange.request(host: "d-gnss.jp", mount: "RRSGD2024", user: "docomo-id", password: "secret-pass", dialect: .v1, gga: gga)
        let ok = caster.respond(to: good.bytes)
        XCTAssertEqual(NTRIPExchange.parseHeader(ok)?.reply, .stream)
        XCTAssertEqual(NTRIPExchange.parseHeader(ok)?.body, Data([0xD3, 0x00, 0x13]))

        let noGGA = NTRIPExchange.request(host: "d-gnss.jp", mount: "RRSGD2024", user: "docomo-id", password: "secret-pass", dialect: .v1, gga: nil)
        XCTAssertEqual(NTRIPExchange.parseHeader(caster.respond(to: noGGA.bytes))?.reply, .unavailable)
        XCTAssertEqual(
            NTRIPExchange.parseHeader(caster.respond(to: noGGA.bytes))?.reply.message,
            "同じIDが別の機器で接続中か、一時的に混雑しています。少し待って再接続してください"
        )
        XCTAssertLessThanOrEqual(NTRIPExchange.ggaIntervalSeconds, 5)
        XCTAssertEqual(NTRIPExchange.ggaIntervalSeconds, 2)

        let badAuth = NTRIPExchange.request(host: "d-gnss.jp", mount: "RRSGD2024", user: "docomo-id", password: "wrong", dialect: .v2, gga: gga)
        XCTAssertEqual(NTRIPExchange.parseHeader(caster.respond(to: badAuth.bytes))?.reply, .unauthorized)

        let badMount = NTRIPExchange.request(host: "d-gnss.jp", mount: "RRSGD", user: "docomo-id", password: "secret-pass", dialect: .v1, gga: gga)
        XCTAssertEqual(NTRIPExchange.parseHeader(caster.respond(to: badMount.bytes))?.reply, .missingMount)

        var ugly = String(decoding: good.bytes, as: UTF8.self)
        ugly = ugly.replacingOccurrences(of: "User-Agent: NTRIP artsx/1.1", with: "User-Agent: artsx/1.1")
        XCTAssertEqual(NTRIPExchange.parseHeader(caster.respond(to: Data(ugly.utf8)))?.reply, .unavailable)
    }

    func testSourcetableAndChunkedBody() {
        let list = NTRIPExchange.request(host: "d-gnss.jp", mount: nil, user: "docomo-id", password: "secret-pass", dialect: .v1, gga: nil)
        XCTAssertTrue(String(decoding: list.bytes, as: UTF8.self).hasPrefix("GET / HTTP/1.0\r\n"))
        let table = FakeCaster().respond(to: list.bytes)
        let parsed = NTRIPExchange.parseHeader(table)
        XCTAssertEqual(parsed?.reply, .sourcetable)
        XCTAssertEqual(NTRIPExchange.mounts(in: String(decoding: parsed?.body ?? Data(), as: UTF8.self)), ["RRSGD2024", "RRSGD"])

        let header = Data("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n".utf8)
        let parsedHeader = NTRIPExchange.parseHeader(header + Data("3\r\nABC\r\n0\r\n\r\n".utf8))
        XCTAssertEqual(parsedHeader?.chunked, true)
        var decoder = NTRIPChunkDecoder()
        XCTAssertEqual(decoder.feed(Data("3\r\nAB".utf8)), Data())
        XCTAssertEqual(decoder.feed(Data("C\r\n0\r\n\r\n".utf8)), Data("ABC".utf8))
    }

    func testGGAChecksumAndDiscovery() {
        let sentence = NTRIPExchange.gpgga(latitudeDegrees: -35.5, longitudeDegrees: 136.9021, ellipsoidalHeightMeters: 12.5, at: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(sentence.hasPrefix("$GPGGA,"))
        XCTAssertTrue(sentence.contains(",S,"))
        XCTAssertTrue(sentence.contains(",E,"))
        let body = sentence.dropFirst().split(separator: "*").first.map(String.init) ?? ""
        XCTAssertTrue(sentence.hasSuffix(NTRIPExchange.checksum(body)))

        XCTAssertFalse(ViDocDiscovery.matches(localName: "AirPods"))
        XCTAssertTrue(ViDocDiscovery.matches(localName: "viGram-1842"))
        XCTAssertTrue(ViDocDiscovery.matches(localName: "viDoc VIDAFGH"))
        XCTAssertTrue(ViDocDiscovery.matches(localName: "", serviceDataUUIDs: ["FFE1"]))
        XCTAssertTrue(ViDocDiscovery.matches(localName: "", serviceUUIDs: ["FFE1"]))
        XCTAssertTrue(ViDocDiscovery.matches(localName: "", manufacturerData: Data([0x39, 0x06, 0x01])))
        XCTAssertFalse(ViDocDiscovery.matches(localName: "", manufacturerData: Data([0x4C, 0x00])))
        XCTAssertEqual(Array(ViDocLink.nmeaStartCommand), [0x02, 0x6E, 0x6D, 0x65, 0x61, 0x03])
        let rtcm = Data(repeating: 0xAB, count: 50)
        let chunks = ViDocLink.rtcmChunks(rtcm, maximumWriteLength: 20)
        XCTAssertEqual(chunks.map(\.count), [20, 20, 10])
        XCTAssertEqual(chunks.flatMap { Array($0) }, Array(rtcm))
    }

    func testRTCMChunksStayWithin180AndKeepOrder() {
        XCTAssertEqual(ViDocLink.chunkSize(maximumWriteLength: 244), 180)
        XCTAssertEqual(ViDocLink.chunkSize(maximumWriteLength: 23), 23)
        XCTAssertEqual(ViDocLink.chunkSize(maximumWriteLength: 8), 20)
        XCTAssertEqual(ViDocLink.rtcmChunkIntervalMs, 12)
        XCTAssertTrue((10...15).contains(ViDocLink.rtcmChunkIntervalMs))
        let payload = Data((0..<400).map { UInt8($0 & 0xFF) })
        let chunks = ViDocLink.rtcmChunks(payload, maximumWriteLength: 244)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 180 })
        XCTAssertEqual(chunks.dropLast().map(\.count), [180, 180])
        XCTAssertEqual(chunks.flatMap { Array($0) }, Array(payload))
    }

    func testRTCMPacingHonoursIntervalAndDropsWholeFrames() {
        var schedule = RTCMWriteSchedule(intervalMs: 12)
        XCTAssertTrue(schedule.allows(at: 0, transportReady: true))
        XCTAssertFalse(schedule.allows(at: 0, transportReady: false))
        schedule = schedule.advanced(afterSendingAt: 0)
        XCTAssertFalse(schedule.allows(at: 0.011, transportReady: true))
        XCTAssertTrue(schedule.allows(at: 0.012, transportReady: true))
        XCTAssertEqual(schedule.nextAllowed, 0.012, accuracy: 1e-9)

        var buffer = RTCMOutboundBuffer()
        let frame = Data([0xD3, 0x00, 0x01, 0x11, 0x00, 0x00, 0x00])
        var stream = Data()
        for index in 0..<3_000 {
            var copy = frame
            copy[3] = UInt8(index & 0xFF)
            stream.append(copy)
        }
        buffer.append(stream)
        XCTAssertLessThanOrEqual(buffer.bufferedBytes, RTCMOutboundBuffer.capBytes)
        XCTAssertEqual(buffer.bufferedBytes % frame.count, 0)
        let kept = buffer.bufferedBytes / frame.count
        let dropped = 3_000 - kept
        XCTAssertGreaterThan(dropped, 0)
        var rebuilt = Data()
        while let chunk = buffer.nextChunk(maximumBytes: 180) {
            XCTAssertLessThanOrEqual(chunk.count, 180)
            rebuilt.append(chunk)
        }
        XCTAssertEqual(rebuilt.count, kept * frame.count)
        XCTAssertEqual(rebuilt[3], UInt8(dropped & 0xFF))
    }
}
