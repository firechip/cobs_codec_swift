# Integrating with Swift Concurrency

`CobsCodec` is stdlib-only and Foundation-free by design, so it ships no
`Stream` / Combine glue that would tie it to Apple platforms. Instead, the
public `CobsStreamDecoder` is enough to build the adapter you want in **your**
code. Here is the idiomatic one: an `AsyncSequence` that turns a raw byte stream
into the COBS packets carried on it.

This is a copy-paste recipe, **not** part of the `CobsCodec` module. It is
verified against the module's real API.

## `AsyncSequence<UInt8>` → decoded packets

```swift
import CobsCodec

public struct CobsFrames<Base: AsyncSequence>: AsyncSequence where Base.Element == UInt8 {
    public typealias Element = [UInt8]

    let base: Base
    let reduced: Bool
    let sentinel: UInt8

    public struct AsyncIterator: AsyncIteratorProtocol {
        var base: Base.AsyncIterator
        let decoder: CobsStreamDecoder
        var ready: [[UInt8]] = []
        var next = 0

        public mutating func next() async throws -> [UInt8]? {
            while true {
                if next < ready.count {
                    defer { next += 1 }
                    return ready[next]
                }
                ready.removeAll(keepingCapacity: true)
                next = 0
                guard let byte = try await base.next() else { return nil }
                let frames = try decoder.feed([byte])
                if !frames.isEmpty { ready = frames }
            }
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(
            base: base.makeAsyncIterator(),
            decoder: CobsStreamDecoder(reduced: reduced, sentinel: sentinel))
    }
}

extension AsyncSequence where Element == UInt8 {
    /// Lazily reframes this byte stream (e.g. a serial port's `bytes`) into the
    /// COBS packets carried on it. Each delimiter closes a frame.
    public func cobsFrames(reduced: Bool = false, sentinel: UInt8 = 0) -> CobsFrames<Self> {
        CobsFrames(base: self, reduced: reduced, sentinel: sentinel)
    }
}
```

Use it wherever you have an async byte stream:

```swift
for try await packet in serialPort.bytes.cobsFrames() {
    handle(packet)   // one decoded COBS packet
}
```

`CobsStreamDecoder` also takes `maxFrameLength` (a guard against unbounded
buffering on a noisy link) and `skipEmpty` — thread them through `cobsFrames`
the same way as `sentinel` / `reduced` if you need them.

## Encoding

The write direction needs no adapter: `Framing.frame(_:reduced:sentinel:)`
already returns a ready-to-send `[UInt8]` (COBS + delimiter) for each packet, so
mapping a sequence of packets to wire bytes is a one-liner.

## What stays in the core

`Cobs` / `Cobsr` encode/decode (with sentinel and in-place variants), `Framing`
for `0x00`-delimited streams, the incremental `CobsStreamDecoder`, and the
`encodingOverhead` / `maxEncodedLength` helpers. The adapter above is just the
seam where Swift Concurrency meets that API.
