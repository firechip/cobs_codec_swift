//
//  Cobs.swift
//  CobsCodec
//
//  Basic Consistent Overhead Byte Stuffing (COBS).
//

/// Basic Consistent Overhead Byte Stuffing (COBS).
///
/// COBS encodes an arbitrary byte sequence into one that contains no zero
/// (`0x00`) byte, at a small and predictable cost (see ``maxEncodedLength(_:)``).
/// A single `0x00` can therefore delimit encoded packets on a byte stream. The
/// `sentinel` parameter generalises this: encoding XORs every output byte with
/// `sentinel`, so the output avoids the `sentinel` byte instead of `0x00` and
/// `sentinel` can serve as the delimiter. `sentinel == 0` is the plain codec.
public enum Cobs {
    /// Encodes `input` with basic COBS.
    ///
    /// The output never contains the `sentinel` byte. Encoding never fails: any
    /// input is encodable, and the empty input encodes to `[0x01]` (or, with a
    /// non-zero sentinel, `[0x01 ^ sentinel]`).
    ///
    /// - Parameters:
    ///   - input: The raw bytes to encode.
    ///   - sentinel: The byte the encoding must avoid. `0` (the default) means
    ///     plain COBS, avoiding `0x00`.
    /// - Returns: The COBS-encoded bytes.
    public static func encode(_ input: [UInt8], sentinel: UInt8 = 0) -> [UInt8] {
        var output = rawEncode(input)
        if sentinel != 0 {
            for i in output.indices {
                output[i] ^= sentinel
            }
        }
        return output
    }

    /// Decodes basic-COBS `input`.
    ///
    /// The empty input decodes to an empty array. `input` must be a single
    /// encoded packet with no surrounding delimiter bytes.
    ///
    /// - Parameters:
    ///   - input: The COBS-encoded bytes to decode.
    ///   - sentinel: The sentinel byte the data was encoded with. `0` (the
    ///     default) means plain COBS.
    /// - Returns: The decoded bytes.
    /// - Throws: ``CobsDecodeError/zeroByte(index:)`` if a forbidden byte
    ///   appears in the input, or ``CobsDecodeError/truncated(index:)`` if a
    ///   length code points past the end of the input.
    public static func decode(_ input: [UInt8], sentinel: UInt8 = 0) throws -> [UInt8] {
        let srcLen = input.count
        if srcLen == 0 {
            return []
        }

        // COBS never expands, so the decoded output fits in `srcLen` bytes.
        var output = [UInt8](repeating: 0, count: srcLen)
        var writeIndex = 0
        var index = 0

        while true {
            let code = input[index] ^ sentinel
            if code == 0 {
                throw CobsDecodeError.zeroByte(index: index)
            }
            index += 1
            let blockEnd = index + Int(code) - 1
            let copyEnd = min(blockEnd, srcLen)
            while index < copyEnd {
                let byte = input[index] ^ sentinel
                if byte == 0 {
                    throw CobsDecodeError.zeroByte(index: index)
                }
                output[writeIndex] = byte
                writeIndex += 1
                index += 1
            }
            if blockEnd > srcLen {
                throw CobsDecodeError.truncated(index: blockEnd - Int(code))
            }
            if blockEnd < srcLen {
                if code < 0xFF {
                    output[writeIndex] = 0
                    writeIndex += 1
                }
            } else {
                break
            }
        }

        output.removeLast(srcLen - writeIndex)
        return output
    }

    /// Decodes basic-COBS data in place, overwriting the start of `buffer` with
    /// the decoded output and returning its length. The decoded bytes occupy
    /// `buffer[0..<n]`; any bytes beyond `n` are left unspecified.
    ///
    /// COBS decoding never expands, so the write position always trails the read
    /// position and no separate output buffer is needed.
    ///
    /// - Parameters:
    ///   - buffer: The COBS-encoded bytes, decoded in place.
    ///   - sentinel: The sentinel byte the data was encoded with. `0` (the
    ///     default) means plain COBS.
    /// - Returns: The number of decoded bytes, occupying `buffer[0..<n]`.
    /// - Throws: ``CobsDecodeError/zeroByte(index:)`` or
    ///   ``CobsDecodeError/truncated(index:)`` if `buffer` is not valid COBS.
    @discardableResult
    public static func decodeInPlace(_ buffer: inout [UInt8], sentinel: UInt8 = 0) throws -> Int {
        let srcLen = buffer.count
        if srcLen == 0 {
            return 0
        }

        var writeIndex = 0
        var index = 0

        while true {
            let code = buffer[index] ^ sentinel
            if code == 0 {
                throw CobsDecodeError.zeroByte(index: index)
            }
            index += 1
            let blockEnd = index + Int(code) - 1
            let copyEnd = min(blockEnd, srcLen)
            while index < copyEnd {
                let byte = buffer[index] ^ sentinel
                if byte == 0 {
                    throw CobsDecodeError.zeroByte(index: index)
                }
                // writeIndex < index throughout, so this never clobbers unread
                // input.
                buffer[writeIndex] = byte
                writeIndex += 1
                index += 1
            }
            if blockEnd > srcLen {
                throw CobsDecodeError.truncated(index: blockEnd - Int(code))
            }
            if blockEnd < srcLen {
                if code < 0xFF {
                    buffer[writeIndex] = 0
                    writeIndex += 1
                }
            } else {
                break
            }
        }

        return writeIndex
    }

    /// Encodes `src` with basic COBS, avoiding `0x00`, without the sentinel XOR.
    private static func rawEncode(_ src: [UInt8]) -> [UInt8] {
        if src.isEmpty {
            return [0x01]
        }

        let srcLen = src.count
        var dst = [UInt8](repeating: 0, count: maxEncodedLength(srcLen))
        var codeIndex = 0
        var writeIndex = 1
        var code: UInt8 = 1
        var readIndex = 0

        while true {
            let byte = src[readIndex]
            readIndex += 1
            if byte == 0 {
                dst[codeIndex] = code
                codeIndex = writeIndex
                writeIndex += 1
                code = 1
                if readIndex >= srcLen {
                    break
                }
            } else {
                dst[writeIndex] = byte
                writeIndex += 1
                code += 1
                // Terminate before the 0xFF split so a run of exactly 254
                // non-zero bytes does not emit a spurious trailing block.
                if readIndex >= srcLen {
                    break
                }
                if code == 0xFF {
                    dst[codeIndex] = code
                    codeIndex = writeIndex
                    writeIndex += 1
                    code = 1
                }
            }
        }
        dst[codeIndex] = code

        dst.removeLast(dst.count - writeIndex)
        return dst
    }
}
