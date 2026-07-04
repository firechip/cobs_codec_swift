//
//  Overhead.swift
//  CobsCodec
//
//  Encoding-overhead helpers and shared constants.
//

/// The largest number of source bytes a single COBS code block can carry
/// without emitting an overhead byte.
///
/// A code byte of `0xFF` represents a run of exactly this many non-zero data
/// bytes with no trailing implicit zero.
public let cobsMaxBlockLength = 254

/// Returns the maximum encoding overhead, in bytes, that COBS or COBS/R can add
/// when encoding a message of `sourceLength` bytes.
///
/// COBS adds at most one byte per ``cobsMaxBlockLength`` (254) bytes of input,
/// rounded up, and at least one byte for any message — including the empty one.
/// In closed form this is `ceil(n / 254)` for a non-empty message of `n` bytes,
/// and `1` for the empty message.
///
/// - Parameter sourceLength: The length, in bytes, of the message to encode.
/// - Returns: The worst-case overhead in bytes.
///
/// ```swift
/// encodingOverhead(0)   // 1
/// encodingOverhead(254) // 1
/// encodingOverhead(255) // 2
/// ```
public func encodingOverhead(_ sourceLength: Int) -> Int {
    if sourceLength == 0 {
        return 1
    }
    return 1 + (sourceLength - 1) / cobsMaxBlockLength
}

/// Returns the maximum possible length, in bytes, of the COBS (or COBS/R)
/// encoding of a message of `sourceLength` bytes.
///
/// Useful for sizing an encode buffer. For a message of `n` bytes this is
/// `n + ceil(n / 254)` (and `1` when `n == 0`). COBS/R output is never larger
/// than this bound.
///
/// - Parameter sourceLength: The length, in bytes, of the message to encode.
/// - Returns: The worst-case encoded length in bytes.
///
/// ```swift
/// maxEncodedLength(254) // 255
/// maxEncodedLength(255) // 257
/// ```
public func maxEncodedLength(_ sourceLength: Int) -> Int {
    return sourceLength + encodingOverhead(sourceLength)
}
