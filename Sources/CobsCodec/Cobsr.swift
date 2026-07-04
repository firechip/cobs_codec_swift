//
//  Cobsr.swift
//  CobsCodec
//
//  Consistent Overhead Byte Stuffing, Reduced (COBS/R).
//

/// Consistent Overhead Byte Stuffing, Reduced (COBS/R).
///
/// COBS/R is identical to ``Cobs`` except that, when the final data byte's value
/// is greater than or equal to the final length code, that byte is used as the
/// length code and dropped from the tail — saving one byte. This often avoids
/// the `+1` byte basic COBS always adds, which matters for small messages. The
/// output is never larger than the basic-COBS encoding, and can be as small as
/// the input (zero overhead).
///
/// When decoding, a length code that points past the end of the input is not an
/// error but the reduced final block, whose single data byte is the code value
/// itself. COBS/R therefore never throws ``CobsDecodeError/truncated(index:)``.
public enum Cobsr {
    /// Encodes `input` with COBS/R.
    ///
    /// The output never contains the `sentinel` byte and is never larger than
    /// the basic-COBS encoding. The empty input encodes to `[0x01]` (or, with a
    /// non-zero sentinel, `[0x01 ^ sentinel]`).
    ///
    /// - Parameters:
    ///   - input: The raw bytes to encode.
    ///   - sentinel: The byte the encoding must avoid. `0` (the default) means
    ///     plain COBS/R, avoiding `0x00`.
    /// - Returns: The COBS/R-encoded bytes.
    public static func encode(_ input: [UInt8], sentinel: UInt8 = 0) -> [UInt8] {
        var output = rawEncode(input)
        if sentinel != 0 {
            for i in output.indices {
                output[i] ^= sentinel
            }
        }
        return output
    }

    /// Decodes COBS/R `input`.
    ///
    /// The empty input decodes to an empty array. Unlike ``Cobs/decode(_:sentinel:)``,
    /// a length code that points past the end of the input is not an error: it
    /// signals the reduced final block.
    ///
    /// - Parameters:
    ///   - input: The COBS/R-encoded bytes to decode.
    ///   - sentinel: The sentinel byte the data was encoded with. `0` (the
    ///     default) means plain COBS/R.
    /// - Returns: The decoded bytes.
    /// - Throws: ``CobsDecodeError/zeroByte(index:)`` if a forbidden byte
    ///   appears in the input.
    public static func decode(_ input: [UInt8], sentinel: UInt8 = 0) throws -> [UInt8] {
        let srcLen = input.count
        if srcLen == 0 {
            return []
        }

        // COBS/R never expands, so the decoded output fits in `srcLen` bytes.
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
                // Reduced encoding: the length code was really the final data byte.
                output[writeIndex] = code
                writeIndex += 1
                break
            } else if blockEnd < srcLen {
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

    /// Decodes COBS/R data in place, overwriting the start of `buffer` with the
    /// decoded output and returning its length. The decoded bytes occupy
    /// `buffer[0..<n]`; any bytes beyond `n` are left unspecified.
    ///
    /// COBS/R decoding never expands, so the write position always trails the
    /// read position. A length code that points past the end of the input is not
    /// an error but the reduced final block, whose data byte is the code value
    /// itself; because all input has then been consumed, that byte is written
    /// onto an already-read position and never clobbers unread input.
    ///
    /// - Parameters:
    ///   - buffer: The COBS/R-encoded bytes, decoded in place.
    ///   - sentinel: The sentinel byte the data was encoded with. `0` (the
    ///     default) means plain COBS/R.
    /// - Returns: The number of decoded bytes, occupying `buffer[0..<n]`.
    /// - Throws: ``CobsDecodeError/zeroByte(index:)`` if `buffer` contains a
    ///   forbidden byte.
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
                // Reduced encoding: the length code was really the final data
                // byte. All input is consumed, so this write lands on an
                // already-read byte.
                buffer[writeIndex] = code
                writeIndex += 1
                break
            } else if blockEnd < srcLen {
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

    /// Encodes `src` with COBS/R, avoiding `0x00`, without the sentinel XOR.
    private static func rawEncode(_ src: [UInt8]) -> [UInt8] {
        let srcLen = src.count
        var dst = [UInt8](repeating: 0, count: maxEncodedLength(srcLen))
        var codeIndex = 0
        var writeIndex = 1
        var code: UInt8 = 1
        var lastByte: UInt8 = 0

        if srcLen != 0 {
            var readIndex = 0
            while true {
                let byte = src[readIndex]
                readIndex += 1
                lastByte = byte
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
        }

        // Reduction: if the final data byte's value is >= the length code basic
        // COBS would write, use that byte as the length code and drop it from
        // the tail.
        if lastByte < code {
            dst[codeIndex] = code
        } else {
            dst[codeIndex] = lastByte
            writeIndex -= 1
        }

        dst.removeLast(dst.count - writeIndex)
        return dst
    }
}
