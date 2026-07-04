//
//  HexHelpers.swift
//  CobsCodecTests
//
//  Small hex <-> [UInt8] helpers shared by the test suites.
//

import Foundation

/// Decodes a lowercase/uppercase hex string into bytes. Returns `nil` on a
/// malformed string (odd length or non-hex digit).
func bytesFromHex(_ hex: String) -> [UInt8]? {
    let chars = Array(hex.utf8)
    if chars.count % 2 != 0 {
        return nil
    }
    var out = [UInt8]()
    out.reserveCapacity(chars.count / 2)

    func nibble(_ c: UInt8) -> UInt8? {
        switch c {
        case 0x30...0x39: return c - 0x30  // '0'..'9'
        case 0x61...0x66: return c - 0x61 + 10  // 'a'..'f'
        case 0x41...0x46: return c - 0x41 + 10  // 'A'..'F'
        default: return nil
        }
    }

    var i = 0
    while i < chars.count {
        guard let hi = nibble(chars[i]), let lo = nibble(chars[i + 1]) else {
            return nil
        }
        out.append((hi << 4) | lo)
        i += 2
    }
    return out
}

/// Encodes bytes into a lowercase hex string.
func hexFromBytes(_ bytes: [UInt8]) -> String {
    let digits = Array("0123456789abcdef".utf8)
    var out = [UInt8]()
    out.reserveCapacity(bytes.count * 2)
    for b in bytes {
        out.append(digits[Int(b >> 4)])
        out.append(digits[Int(b & 0x0F)])
    }
    return String(decoding: out, as: UTF8.self)
}
