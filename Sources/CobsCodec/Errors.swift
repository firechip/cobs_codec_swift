//
//  Errors.swift
//  CobsCodec
//
//  Error types shared by the COBS and COBS/R decoders and the framing helpers.
//

/// An error returned when decoding COBS or COBS/R data fails.
///
/// The associated `index` values match the byte positions reported by the
/// reference Firechip COBS implementations, so error locations are portable
/// across the family. COBS/R never throws ``truncated(index:)``: a length code
/// that points past the end of its input is not an error there but the signal
/// for the reduced final block.
public enum CobsDecodeError: Error, Equatable {
    /// A zero (`0x00`) byte — or, with a non-zero sentinel, the sentinel byte —
    /// appeared in the encoded input. A valid COBS stream never contains one.
    ///
    /// - Parameter index: Index of the offending byte within the input.
    case zeroByte(index: Int)

    /// A length code claimed more bytes than remain in the input (basic COBS
    /// only). COBS/R interprets that same situation as its reduced final block
    /// and therefore never throws this error.
    ///
    /// - Parameter index: Index of the offending length code within the input.
    case truncated(index: Int)
}

/// An error returned by ``CobsStreamDecoder`` when an unterminated frame grows
/// past its configured maximum length.
///
/// This mirrors the reference streaming decoder's `FrameTooLong` condition. It
/// is distinct from ``CobsDecodeError`` because it concerns frame reassembly
/// (delimiter handling) rather than the COBS decode of a single frame.
public enum CobsFramingError: Error, Equatable {
    /// More than the configured `maxFrameLength` bytes were buffered for a
    /// single frame without encountering the delimiter. The buffer is
    /// discarded and reassembly resumes with the next delimiter.
    ///
    /// - Parameter length: Number of buffered bytes when the limit was exceeded.
    case frameTooLong(length: Int)
}
