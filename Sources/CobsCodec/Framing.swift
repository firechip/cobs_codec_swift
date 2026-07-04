//
//  Framing.swift
//  CobsCodec
//
//  Packet framing helpers built on top of COBS / COBS/R.
//

/// Packet framing helpers built on top of COBS and COBS/R.
///
/// Because a COBS-encoded packet never contains the sentinel byte, a single
/// sentinel byte can delimit encoded packets on a byte stream such as a
/// serial/UART link. ``frame(_:reduced:sentinel:)`` appends that delimiter and
/// ``unframe(_:reduced:skipEmpty:sentinel:)`` splits a buffer back into packets.
/// For streaming input arriving in arbitrary chunks, use ``CobsStreamDecoder``.
public enum Framing {
    /// The default byte value used to delimit COBS-encoded frames on the wire.
    ///
    /// When a non-zero `sentinel` is used, that sentinel byte is the delimiter
    /// instead (the encoding is arranged to avoid it).
    public static let delimiter: UInt8 = 0

    /// Encodes `packet` and appends the delimiter, returning the framed bytes.
    ///
    /// The delimiter is `sentinel` (which the encoding avoids); with the default
    /// `sentinel == 0` it is `0x00`.
    ///
    /// - Parameters:
    ///   - packet: The raw packet bytes to frame.
    ///   - reduced: Use COBS/R (``Cobsr``) instead of basic COBS (``Cobs``).
    ///   - sentinel: The byte the encoding avoids and that delimits the frame.
    /// - Returns: The encoded packet followed by the delimiter byte.
    public static func frame(_ packet: [UInt8], reduced: Bool = false, sentinel: UInt8 = 0) -> [UInt8] {
        var output = reduced
            ? Cobsr.encode(packet, sentinel: sentinel)
            : Cobs.encode(packet, sentinel: sentinel)
        output.append(sentinel)
        return output
    }

    /// Splits `data` on the delimiter and decodes each frame, returning the
    /// decoded packets in order.
    ///
    /// The delimiter is `sentinel`. A trailing partial frame with no terminating
    /// delimiter is not decoded (it is treated as incomplete), so
    /// `unframe(frame(p))` round-trips to `[p]`.
    ///
    /// - Parameters:
    ///   - data: The framed byte stream to split and decode.
    ///   - reduced: Decode frames as COBS/R (``Cobsr``) instead of basic COBS.
    ///   - skipEmpty: Skip empty frames (from consecutive or leading
    ///     delimiters) rather than emit empty packets. Defaults to `true`.
    ///   - sentinel: The sentinel byte the frames were encoded with, which also
    ///     delimits them.
    /// - Returns: The decoded packets, in order.
    /// - Throws: A ``CobsDecodeError`` if any complete frame fails to decode.
    public static func unframe(
        _ data: [UInt8],
        reduced: Bool = false,
        skipEmpty: Bool = true,
        sentinel: UInt8 = 0
    ) throws -> [[UInt8]] {
        var frames: [[UInt8]] = []
        var start = 0
        for i in data.indices {
            if data[i] != sentinel {
                continue
            }
            let frame = Array(data[start..<i])
            start = i + 1
            if frame.isEmpty {
                if !skipEmpty {
                    frames.append([])
                }
                continue
            }
            let decoded = reduced
                ? try Cobsr.decode(frame, sentinel: sentinel)
                : try Cobs.decode(frame, sentinel: sentinel)
            frames.append(decoded)
        }
        return frames
    }
}

/// A streaming decoder that reassembles delimiter-framed COBS (or COBS/R)
/// packets from a byte stream arriving in arbitrarily sized chunks.
///
/// This is the natural way to read COBS packets from a serial/UART link: feed
/// raw bytes with ``feed(_:)`` as they arrive and receive whole decoded packets
/// once their delimiter is seen. Frames may straddle any number of chunk
/// boundaries.
public final class CobsStreamDecoder {
    private var buffer: [UInt8] = []
    private let reduced: Bool
    private let skipEmpty: Bool
    private let maxFrameLength: Int
    private let sentinel: UInt8

    /// Creates a streaming decoder.
    ///
    /// - Parameters:
    ///   - reduced: Decode frames as COBS/R (``Cobsr``) instead of basic COBS.
    ///     Defaults to `false`.
    ///   - skipEmpty: Skip empty frames (from consecutive or leading
    ///     delimiters) rather than emit empty packets. Defaults to `true`.
    ///   - maxFrameLength: Upper bound, in bytes, on a single unterminated
    ///     frame's buffered length. When exceeded, the buffer is discarded and
    ///     ``feed(_:)`` throws ``CobsFramingError/frameTooLong(length:)``. `0`
    ///     (the default) means unbounded.
    ///   - sentinel: The sentinel byte the frames were encoded with, which also
    ///     delimits them. Defaults to `0`.
    public init(
        reduced: Bool = false,
        skipEmpty: Bool = true,
        maxFrameLength: Int = 0,
        sentinel: UInt8 = 0
    ) {
        self.reduced = reduced
        self.skipEmpty = skipEmpty
        self.maxFrameLength = maxFrameLength
        self.sentinel = sentinel
    }

    /// Feeds a chunk of raw bytes, returning every frame that completes within
    /// this chunk (in order). Bytes after the last delimiter are buffered for a
    /// later call.
    ///
    /// - Parameter chunk: The next run of raw bytes from the stream.
    /// - Returns: The decoded packets completed by this chunk, in order.
    /// - Throws: A ``CobsDecodeError`` if a completed frame fails to decode, or
    ///   ``CobsFramingError/frameTooLong(length:)`` if the trailing partial
    ///   frame exceeds `maxFrameLength`.
    public func feed(_ chunk: [UInt8]) throws -> [[UInt8]] {
        var frames: [[UInt8]] = []
        var start = 0
        for i in chunk.indices {
            if chunk[i] != sentinel {
                continue
            }
            buffer.append(contentsOf: chunk[start..<i])
            start = i + 1
            let frame = buffer
            buffer.removeAll(keepingCapacity: true)
            if frame.isEmpty {
                if !skipEmpty {
                    frames.append([])
                }
                continue
            }
            let decoded = reduced
                ? try Cobsr.decode(frame, sentinel: sentinel)
                : try Cobs.decode(frame, sentinel: sentinel)
            frames.append(decoded)
        }
        if start < chunk.count {
            buffer.append(contentsOf: chunk[start...])
            if maxFrameLength != 0 && buffer.count > maxFrameLength {
                let len = buffer.count
                buffer.removeAll(keepingCapacity: true)
                throw CobsFramingError.frameTooLong(length: len)
            }
        }
        return frames
    }

    /// Discards any buffered partial frame, resetting the decoder to its initial
    /// state.
    public func reset() {
        buffer.removeAll(keepingCapacity: true)
    }
}
