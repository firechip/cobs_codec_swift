# Changelog

All notable changes to this package are documented here. This project adheres to
[Semantic Versioning](https://semver.org).

## 1.0.0

Initial release.

### Added

- Pure-Swift (stdlib-only), dependency-free **basic COBS** and **COBS/R**
  encode/decode with a configurable `sentinel:` byte (`Cobs`, `Cobsr`).
- In-place decoding (`decodeInPlace`), stream framing (`Framing.frame`/`unframe`),
  and an incremental `CobsStreamDecoder` with a `maxFrameLength` guard.
- Size helpers `maxEncodedLength` / `encodingOverhead`, and typed
  `CobsDecodeError` / `CobsFramingError`.
- Multiplatform: macOS 13+, iOS 16+, tvOS 16+, watchOS 9+, and Linux.
- Verified byte-identical against
  [firechip/cobs-conformance](https://github.com/firechip/cobs-conformance)
  (basic, COBS/R, sentinel, and decode-error vectors).
