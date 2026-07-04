//
//  GoldenTests.swift
//  CobsCodecTests
//
//  Golden-vector, round-trip, sentinel, in-place, and framing tests that run
//  with no external inputs (so `swift test` is green on its own).
//

import XCTest

@testable import CobsCodec

final class GoldenTests: XCTestCase {
    // MARK: - Golden vectors (a handful mirrored from the COBS family)

    /// (decoded, cobs, cobsr) triples, hex-encoded. Mirrored verbatim from the
    /// shared conformance vectors so the in-repo goldens can't drift.
    private let golden: [(decoded: String, cobs: String, cobsr: String)] = [
        ("", "01", "01"),
        ("00", "0101", "0101"),
        ("02", "0202", "02"),
        ("11", "0211", "11"),
        ("ff", "02ff", "ff"),
        ("0102", "030102", "030102"),
        ("0100", "020101", "020101"),
        ("01020300", "0401020301", "0401020301"),
        ("00010203", "0104010203", "0104010203"),
        ("00000000", "0101010101", "0101010101"),
    ]

    func testGoldenCobsEncode() {
        for v in golden {
            let decoded = bytesFromHex(v.decoded)!
            let expected = bytesFromHex(v.cobs)!
            XCTAssertEqual(Cobs.encode(decoded), expected, "cobs encode \(v.decoded)")
        }
    }

    func testGoldenCobsDecode() throws {
        for v in golden {
            let decoded = bytesFromHex(v.decoded)!
            let encoded = bytesFromHex(v.cobs)!
            XCTAssertEqual(try Cobs.decode(encoded), decoded, "cobs decode \(v.cobs)")
        }
    }

    func testGoldenCobsrEncode() {
        for v in golden {
            let decoded = bytesFromHex(v.decoded)!
            let expected = bytesFromHex(v.cobsr)!
            XCTAssertEqual(Cobsr.encode(decoded), expected, "cobsr encode \(v.decoded)")
        }
    }

    func testGoldenCobsrDecode() throws {
        for v in golden {
            let decoded = bytesFromHex(v.decoded)!
            let encoded = bytesFromHex(v.cobsr)!
            XCTAssertEqual(try Cobsr.decode(encoded), decoded, "cobsr decode \(v.cobsr)")
        }
    }

    // MARK: - Block-boundary cases (254 / 255 non-zero bytes)

    func testCobsRoundTripBlockBoundaries() throws {
        for n in [253, 254, 255, 256, 510] {
            let data = (0..<n).map { UInt8(($0 % 255) + 1) }  // no zeros
            let encoded = Cobs.encode(data)
            XCTAssertFalse(encoded.contains(0), "n=\(n) output has zero")
            XCTAssertEqual(try Cobs.decode(encoded), data, "cobs round trip n=\(n)")
            XCTAssertLessThanOrEqual(encoded.count, maxEncodedLength(n))
        }
    }

    // MARK: - Round trips over a range of payloads

    func testRoundTripsAcrossPayloads() throws {
        var payloads: [[UInt8]] = [[], [0], [0, 0], [1, 2, 3], [0, 1, 0, 2, 0]]
        // A pseudo-random spread of lengths and byte values.
        var state: UInt64 = 0x1234_5678_9abc_def0
        func next() -> UInt8 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return UInt8((state >> 33) & 0xFF)
        }
        for len in 0..<300 {
            payloads.append((0..<len).map { _ in next() })
        }

        for p in payloads {
            let c = Cobs.encode(p)
            XCTAssertFalse(c.contains(0))
            XCTAssertEqual(try Cobs.decode(c), p)

            let r = Cobsr.encode(p)
            XCTAssertFalse(r.contains(0))
            XCTAssertLessThanOrEqual(r.count, c.count, "cobsr never larger than cobs")
            XCTAssertEqual(try Cobsr.decode(r), p)
        }
    }

    // MARK: - Sentinel round trips

    func testSentinelRoundTrips() throws {
        let payloads: [[UInt8]] = [[], [0], [0x11], [0x11, 0x00, 0x22], [1, 2, 3, 4, 5]]
        for sentinel: UInt8 in [0x00, 0x01, 0x55, 0xAB, 0xFF] {
            for p in payloads {
                let c = Cobs.encode(p, sentinel: sentinel)
                if sentinel != 0 {
                    XCTAssertFalse(
                        c.contains(sentinel), "cobs output must avoid sentinel \(sentinel)")
                }
                XCTAssertEqual(try Cobs.decode(c, sentinel: sentinel), p)

                let r = Cobsr.encode(p, sentinel: sentinel)
                if sentinel != 0 {
                    XCTAssertFalse(
                        r.contains(sentinel), "cobsr output must avoid sentinel \(sentinel)")
                }
                XCTAssertEqual(try Cobsr.decode(r, sentinel: sentinel), p)
            }
        }
    }

    // MARK: - In-place vs. normal differential

    func testDecodeInPlaceMatchesNormal() throws {
        var state: UInt64 = 0xdead_beef_cafe_babe
        func next() -> UInt8 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return UInt8((state >> 33) & 0xFF)
        }
        for sentinel: UInt8 in [0x00, 0x7F, 0xFF] {
            for len in 0..<260 {
                let p = (0..<len).map { _ in next() }

                let c = Cobs.encode(p, sentinel: sentinel)
                var cBuf = c
                let cn = try Cobs.decodeInPlace(&cBuf, sentinel: sentinel)
                XCTAssertEqual(Array(cBuf[0..<cn]), try Cobs.decode(c, sentinel: sentinel))
                XCTAssertEqual(Array(cBuf[0..<cn]), p)

                let r = Cobsr.encode(p, sentinel: sentinel)
                var rBuf = r
                let rn = try Cobsr.decodeInPlace(&rBuf, sentinel: sentinel)
                XCTAssertEqual(Array(rBuf[0..<rn]), try Cobsr.decode(r, sentinel: sentinel))
                XCTAssertEqual(Array(rBuf[0..<rn]), p)
            }
        }
    }

    // MARK: - Decode error locations

    func testDecodeErrors() {
        // Zero byte in the input.
        XCTAssertThrowsError(try Cobs.decode([0x00])) { err in
            XCTAssertEqual(err as? CobsDecodeError, .zeroByte(index: 0))
        }
        XCTAssertThrowsError(try Cobs.decode([0x02, 0x11, 0x00, 0x22])) { err in
            XCTAssertEqual(err as? CobsDecodeError, .zeroByte(index: 2))
        }
        // Truncated: length code points past the end (basic COBS only).
        XCTAssertThrowsError(try Cobs.decode([0x05, 0x11])) { err in
            XCTAssertEqual(err as? CobsDecodeError, .truncated(index: 0))
        }
        // COBS/R never throws truncated: it is the reduced final block.
        XCTAssertEqual(try Cobsr.decode([0x05, 0x11]), [0x11, 0x05])
        // COBS/R still rejects a zero byte.
        XCTAssertThrowsError(try Cobsr.decode([0x00])) { err in
            XCTAssertEqual(err as? CobsDecodeError, .zeroByte(index: 0))
        }
    }

    // MARK: - Overhead helpers

    func testOverheadHelpers() {
        XCTAssertEqual(cobsMaxBlockLength, 254)
        XCTAssertEqual(encodingOverhead(0), 1)
        XCTAssertEqual(encodingOverhead(254), 1)
        XCTAssertEqual(encodingOverhead(255), 2)
        XCTAssertEqual(maxEncodedLength(254), 255)
        XCTAssertEqual(maxEncodedLength(255), 257)
    }

    // MARK: - Framing

    func testFrameUnframeRoundTrip() throws {
        let packets: [[UInt8]] = [[0x11, 0x00, 0x22], [1, 2, 3], [], [0]]
        for reduced in [false, true] {
            for sentinel: UInt8 in [0x00, 0x33] {
                var wire: [UInt8] = []
                var nonEmpty: [[UInt8]] = []
                for p in packets {
                    wire += Framing.frame(p, reduced: reduced, sentinel: sentinel)
                    nonEmpty.append(p)
                }
                let out = try Framing.unframe(
                    wire, reduced: reduced, skipEmpty: false, sentinel: sentinel)
                XCTAssertEqual(out, nonEmpty, "reduced=\(reduced) sentinel=\(sentinel)")
            }
        }
    }

    func testFrameSingleRoundTrip() throws {
        let p: [UInt8] = [0x11, 0x00, 0x22]
        let wire = Framing.frame(p)
        XCTAssertEqual(wire.last, Framing.delimiter)
        XCTAssertEqual(try Framing.unframe(wire), [p])
    }

    func testStreamDecoderReassemblesAcrossChunks() throws {
        let packets: [[UInt8]] = [[0x11, 0x00, 0x22], [0x33], [1, 2, 3, 4, 5]]
        var wire: [UInt8] = []
        for p in packets {
            wire += Framing.frame(p)
        }

        // Feed one byte at a time to prove reassembly across arbitrary boundaries.
        let dec = CobsStreamDecoder()
        var got: [[UInt8]] = []
        for b in wire {
            got += try dec.feed([b])
        }
        XCTAssertEqual(got, packets)

        // Feed the whole thing at once.
        let dec2 = CobsStreamDecoder()
        XCTAssertEqual(try dec2.feed(wire), packets)
    }

    func testStreamDecoderReduced() throws {
        let packets: [[UInt8]] = [[0x11], [0x11, 0x22], [0xFE]]
        var wire: [UInt8] = []
        for p in packets {
            wire += Framing.frame(p, reduced: true)
        }
        let dec = CobsStreamDecoder(reduced: true)
        var got: [[UInt8]] = []
        for b in wire {
            got += try dec.feed([b])
        }
        XCTAssertEqual(got, packets)
    }

    func testStreamDecoderMaxFrameLength() {
        let dec = CobsStreamDecoder(maxFrameLength: 4)
        XCTAssertThrowsError(try dec.feed([0x02, 0x02, 0x02, 0x02, 0x02])) { err in
            XCTAssertEqual(err as? CobsFramingError, .frameTooLong(length: 5))
        }
    }

    func testStreamDecoderReset() throws {
        let dec = CobsStreamDecoder()
        _ = try dec.feed([0x02, 0x11])  // partial frame, no delimiter yet
        dec.reset()
        // After reset the buffered partial frame is gone; a fresh frame decodes.
        let frames = try dec.feed(Framing.frame([0x33]))
        XCTAssertEqual(frames, [[0x33]])
    }
}
