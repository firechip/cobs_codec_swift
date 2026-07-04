//
//  main.swift
//  cobs-bench
//
//  A small throughput benchmark for the CobsCodec library.
//
//  Times `Cobs.encode`, `Cobs.decode`, and `Cobsr.encode` over a fixed 1 KiB
//  payload and reports throughput in MB/s (payload bytes / wall time). This is
//  dev-only tooling; it is not part of the shipped library.
//

import CobsCodec
import Foundation

/// Number of payload bytes benchmarked per operation (1 KiB).
let payloadLength = 1024

/// Iterations timed per measurement.
let iterations = 2_000_000

/// Iterations run untimed before each measurement to warm caches and the JIT-free
/// release code paths.
let warmupIterations = 100_000

/// Builds a deterministic 1 KiB payload that is mostly non-zero with roughly one
/// in eight bytes set to `0x00`, so the COBS block-splitting path is exercised.
///
/// A 64-bit linear-congruential generator produces the pseudo-random stream; the
/// fixed seed makes the payload identical on every run.
func makePayload() -> [UInt8] {
    var state: UInt64 = 0x9E37_79B9_7F4A_7C15
    func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }

    var payload = [UInt8](repeating: 0, count: payloadLength)
    for i in 0..<payloadLength {
        let r = next()
        if (r >> 32) & 0x7 == 0 {
            // ~1 in 8 bytes is zero.
            payload[i] = 0
        } else {
            // Otherwise a guaranteed-non-zero byte in 1...255.
            payload[i] = UInt8((r >> 40) % 255) + 1
        }
    }
    return payload
}

/// Runs `body` `iterations` times under a monotonic clock, folding each returned
/// value into an accumulator so the optimizer cannot discard the work.
///
/// - Returns: The elapsed wall time and the accumulated sink value.
func timeLoop(_ body: () -> UInt64) -> (elapsed: Duration, sink: UInt64) {
    var sink: UInt64 = 0
    let clock = ContinuousClock()
    let start = clock.now
    for _ in 0..<iterations {
        sink = sink &+ body()
    }
    return (clock.now - start, sink)
}

/// Converts a `Duration` to seconds as a `Double`.
func seconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) + Double(components.attoseconds) / 1e18
}

/// Throughput in MB/s, where MB is 1_000_000 bytes and the byte count is the
/// payload size times the iteration count.
func megabytesPerSecond(_ duration: Duration) -> Double {
    let totalBytes = Double(iterations) * Double(payloadLength)
    return totalBytes / seconds(duration) / 1e6
}

let payload = makePayload()
let encoded = Cobs.encode(payload)
let zeroCount = payload.lazy.filter { $0 == 0 }.count

// Warm up each measured operation.
for _ in 0..<warmupIterations {
    _ = Cobs.encode(payload)
    _ = try! Cobs.decode(encoded)
    _ = Cobsr.encode(payload)
}

let encodeResult = timeLoop { UInt64(Cobs.encode(payload).count) }
let decodeResult = timeLoop { UInt64(try! Cobs.decode(encoded).count) }
let cobsrResult = timeLoop { UInt64(Cobsr.encode(payload).count) }

// Keep the sinks observable so the compiler retains the timed work.
let sink = encodeResult.sink &+ decodeResult.sink &+ cobsrResult.sink

print("cobs-bench — CobsCodec throughput")
print("payload:      \(payloadLength) bytes, \(zeroCount) zero (~1 in 8)")
print("encoded:      \(encoded.count) bytes")
print("iterations:   \(iterations) (+\(warmupIterations) warmup)")
print("")
print(String(format: "COBS encode:  %8.1f MB/s", megabytesPerSecond(encodeResult.elapsed)))
print(String(format: "COBS decode:  %8.1f MB/s", megabytesPerSecond(decodeResult.elapsed)))
print(String(format: "COBS/R encode:%8.1f MB/s", megabytesPerSecond(cobsrResult.elapsed)))
print("")
print("sink: \(sink)")
