# CobsCodec

[![CI](https://github.com/firechip/cobs_codec_swift/actions/workflows/ci.yml/badge.svg)](https://github.com/firechip/cobs_codec_swift/actions/workflows/ci.yml)
[![Swift 6](https://img.shields.io/badge/swift-6-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20iOS%20%7C%20Linux-lightgrey.svg)](#)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Pure-Swift **Consistent Overhead Byte Stuffing (COBS)** and **COBS/R** codec — the
Swift member of the Firechip COBS family (alongside the
[Rust](https://crates.io/crates/cobs_codec_rs),
[Dart](https://pub.dev/packages/cobs_codec) and
[Kotlin](https://github.com/firechip/cobs_codec_kt) implementations), verified
byte-identical against the shared
[conformance vectors](https://github.com/firechip/cobs-conformance).

COBS encodes an arbitrary byte sequence into one that contains no zero (`0x00`)
byte, at a small, predictable cost (at most one extra byte per 254 bytes, plus
one). A single `0x00` can then reliably delimit packets on a serial/UART, USB, or
BLE link. The `CobsCodec` library is **Swift-standard-library-only** — no
Foundation, no Apple frameworks, no dependencies — so it runs on macOS, iOS,
tvOS, watchOS, and Linux (and embedded Swift).

## Install

Swift Package Manager — add the dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/firechip/cobs_codec_swift.git", from: "1.0.0"),
],
targets: [
    .target(name: "YourTarget", dependencies: ["CobsCodec"]),
]
```

Or in Xcode: **File ▸ Add Package Dependencies…** and paste the repository URL.

## Usage

```swift
import CobsCodec

// Encode / decode a single packet.
let encoded = Cobs.encode([0x11, 0x22, 0x00, 0x33]) // [0x03, 0x11, 0x22, 0x02, 0x33] — no 0x00
let decoded = try Cobs.decode(encoded)              // [0x11, 0x22, 0x00, 0x33]

// COBS/R often saves the trailing overhead byte for small messages.
Cobsr.encode(Array("12345".utf8))                   // [0x35, 0x31, 0x32, 0x33, 0x34] — "51234"

// A custom delimiter byte (sentinel): the output avoids it, so it can delimit
// frames instead of 0x00. `sentinel: 0` is identical to the plain codec.
let stuffed = Cobs.encode([0x11, 0x00, 0x22], sentinel: 0xAA) // [0xA8, 0xBB, 0xA8, 0x88] — no 0xAA
try Cobs.decode(stuffed, sentinel: 0xAA)                      // [0x11, 0x00, 0x22]

// Decode in place, without a second buffer (COBS never expands on decode).
var buffer = Cobs.encode([0x11, 0x00, 0x22])
let n = try Cobs.decodeInPlace(&buffer)             // n == 3; buffer[0..<n] == [0x11, 0x00, 0x22]
```

Reading a delimited serial stream — `CobsStreamDecoder` reassembles packets across
arbitrarily chunked reads (chunks need not align with frames):

```swift
let frame = Framing.frame([0x11, 0x00, 0x22]) // COBS + trailing 0x00 delimiter

let decoder = CobsStreamDecoder(maxFrameLength: 4096)
for chunk in incomingChunks {                 // `chunk` is any [UInt8] read from the link
    for packet in try decoder.feed(chunk) {
        handle(packet)
    }
}
```

Invalid encoded input throws `CobsDecodeError` (`.zeroByte` / `.truncated`).

## Features

- **Basic COBS** and **COBS/R (Reduced)** — `Cobs` and `Cobsr`.
- **Configurable sentinel** — every `encode`/`decode` takes a `sentinel:` byte
  (default `0`) so frames can be delimited by any byte, not just `0x00`.
- **In-place decoding** — `decodeInPlace(_:)` decodes within the buffer.
- **Stream framing** — `Framing.frame`/`unframe` and the incremental
  `CobsStreamDecoder`, with an optional `maxFrameLength` guard.
- **Size helpers** — `maxEncodedLength(_:)` / `encodingOverhead(_:)` for
  pre-allocation; `cobsMaxBlockLength` (`254`).
- **Portable & dependency-free** — Swift-stdlib-only; macOS, iOS, tvOS, watchOS,
  Linux, and embedded Swift.

## Conformance

`CobsCodec` is verified byte-identical against the shared
[firechip/cobs-conformance](https://github.com/firechip/cobs-conformance) vectors
(basic, COBS/R, configurable-sentinel, and decode-error cases) in CI, so it
interoperates exactly with the Rust, Dart, and Kotlin members of the family.

## Benchmarks

Throughput on a 1 KiB payload (`swift run -c release cobs-bench`), Swift 6.2 on an
AMD Ryzen 7 3800XT under WSL2 — indicative (includes result allocation):

| Operation | Throughput |
| --------- | ---------- |
| `Cobs.encode` | ~1090 MB/s |
| `Cobs.decode` | ~1150 MB/s |
| `Cobsr.encode` | ~850 MB/s |

## Integrations

The module stays stdlib-only and Foundation-free, so framework glue lives in
your app rather than in the package. [INTEGRATIONS.md](INTEGRATIONS.md) has a
verified copy-paste recipe: an `AsyncSequence` adapter (`bytes.cobsFrames()`)
that reframes a raw byte stream into decoded packets, built on the public
`CobsStreamDecoder`.

## Background

Stuart Cheshire and Mary Baker, "Consistent Overhead Byte Stuffing",
*IEEE/ACM Transactions on Networking*, Vol. 7, No. 2, April 1999. **COBS/R** is a
variant by Craig McQueen.

## License

MIT © 2026 Alexander Salas Bastidas ([Firechip](https://firechip.dev)). See
[LICENSE](LICENSE).
