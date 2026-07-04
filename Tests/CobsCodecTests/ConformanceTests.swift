//
//  ConformanceTests.swift
//  CobsCodecTests
//
//  Conformance against the shared cross-language JSONL vector files. Each suite
//  is skipped (not failed) when its environment variable is unset, mirroring the
//  other repos in the COBS family.
//
//    COBS_CONFORMANCE_VECTORS  -> {decoded, cobs, cobsr}
//    COBS_CONFORMANCE_SENTINEL -> {decoded, sentinel, cobs, cobsr}
//    COBS_CONFORMANCE_ERRORS   -> {encoded, cobs, cobsr}   (cobs/cobsr may be null)
//

import Foundation
import XCTest

@testable import CobsCodec

final class ConformanceTests: XCTestCase {
    /// Reads the JSONL file at `path`, returning one JSON object per non-empty
    /// line, parsed with `JSONSerialization`.
    private func readJSONL(_ path: String) throws -> [[String: Any]] {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        var rows: [[String: Any]] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                continue
            }
            let data = Data(line.utf8)
            let obj = try JSONSerialization.jsonObject(with: data, options: [])
            guard let dict = obj as? [String: Any] else {
                XCTFail("line is not a JSON object: \(line)")
                continue
            }
            rows.append(dict)
        }
        return rows
    }

    /// The expected outcome of decoding one error-vector field: either an
    /// expected decoded output (hex present) or a required throw (JSON null).
    private enum Expectation {
        case output([UInt8])
        case throwsError
    }

    /// Interprets `dict[key]` as either a hex string (an expected output) or
    /// JSON null (`NSNull`, meaning the decode must throw).
    private func expectation(_ dict: [String: Any], _ key: String) -> Expectation {
        let value = dict[key]
        if value == nil || value is NSNull {
            return .throwsError
        }
        return .output(bytesFromHex(value as! String)!)
    }

    // MARK: - COBS_CONFORMANCE_VECTORS

    func testConformanceVectors() throws {
        guard let path = ProcessInfo.processInfo.environment["COBS_CONFORMANCE_VECTORS"] else {
            throw XCTSkip("COBS_CONFORMANCE_VECTORS not set")
        }
        let rows = try readJSONL(path)
        XCTAssertFalse(rows.isEmpty, "no vectors read from \(path)")
        XCTAssertEqual(rows.count, 2261, "unexpected vector count in \(path)")

        for (n, row) in rows.enumerated() {
            let decoded = bytesFromHex(row["decoded"] as! String)!
            let cobs = bytesFromHex(row["cobs"] as! String)!
            let cobsr = bytesFromHex(row["cobsr"] as! String)!

            // encode matches
            XCTAssertEqual(Cobs.encode(decoded), cobs, "line \(n): cobs encode")
            XCTAssertEqual(Cobsr.encode(decoded), cobsr, "line \(n): cobsr encode")
            // decode matches
            XCTAssertEqual(try Cobs.decode(cobs), decoded, "line \(n): cobs decode")
            XCTAssertEqual(try Cobsr.decode(cobsr), decoded, "line \(n): cobsr decode")
        }
    }

    // MARK: - COBS_CONFORMANCE_SENTINEL

    func testConformanceSentinel() throws {
        guard let path = ProcessInfo.processInfo.environment["COBS_CONFORMANCE_SENTINEL"] else {
            throw XCTSkip("COBS_CONFORMANCE_SENTINEL not set")
        }
        let rows = try readJSONL(path)
        XCTAssertFalse(rows.isEmpty, "no vectors read from \(path)")
        XCTAssertEqual(rows.count, 348, "unexpected vector count in \(path)")

        for (n, row) in rows.enumerated() {
            let decoded = bytesFromHex(row["decoded"] as! String)!
            let sentinelBytes = bytesFromHex(row["sentinel"] as! String)!
            XCTAssertEqual(sentinelBytes.count, 1, "line \(n): sentinel must be one byte")
            let sentinel = sentinelBytes[0]
            let cobs = bytesFromHex(row["cobs"] as! String)!
            let cobsr = bytesFromHex(row["cobsr"] as! String)!

            // sentinel encode matches
            let encCobs = Cobs.encode(decoded, sentinel: sentinel)
            let encCobsr = Cobsr.encode(decoded, sentinel: sentinel)
            XCTAssertEqual(encCobs, cobs, "line \(n): cobs sentinel encode")
            XCTAssertEqual(encCobsr, cobsr, "line \(n): cobsr sentinel encode")
            // sentinel decode matches
            XCTAssertEqual(
                try Cobs.decode(cobs, sentinel: sentinel), decoded,
                "line \(n): cobs sentinel decode")
            XCTAssertEqual(
                try Cobsr.decode(cobsr, sentinel: sentinel), decoded,
                "line \(n): cobsr sentinel decode")
            // output avoids the sentinel byte
            XCTAssertFalse(encCobs.contains(sentinel), "line \(n): cobs output contains sentinel")
            XCTAssertFalse(encCobsr.contains(sentinel), "line \(n): cobsr output contains sentinel")
        }
    }

    // MARK: - COBS_CONFORMANCE_ERRORS

    func testConformanceErrors() throws {
        guard let path = ProcessInfo.processInfo.environment["COBS_CONFORMANCE_ERRORS"] else {
            throw XCTSkip("COBS_CONFORMANCE_ERRORS not set")
        }
        let rows = try readJSONL(path)
        XCTAssertFalse(rows.isEmpty, "no vectors read from \(path)")
        XCTAssertEqual(rows.count, 20, "unexpected vector count in \(path)")

        for (n, row) in rows.enumerated() {
            let encoded = bytesFromHex(row["encoded"] as! String)!

            // `cobs`/`cobsr` are either an expected hex output or JSON null,
            // where null means the decode must throw.
            switch expectation(row, "cobs") {
            case .output(let want):
                XCTAssertEqual(
                    try Cobs.decode(encoded), want,
                    "line \(n): cobs decode of \(hexFromBytes(encoded))")
            case .throwsError:
                XCTAssertThrowsError(
                    try Cobs.decode(encoded), "line \(n): cobs decode should throw")
            }

            switch expectation(row, "cobsr") {
            case .output(let want):
                XCTAssertEqual(
                    try Cobsr.decode(encoded), want,
                    "line \(n): cobsr decode of \(hexFromBytes(encoded))")
            case .throwsError:
                XCTAssertThrowsError(
                    try Cobsr.decode(encoded), "line \(n): cobsr decode should throw")
            }
        }
    }
}
