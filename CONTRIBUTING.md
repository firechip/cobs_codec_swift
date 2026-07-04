# Contributing to CobsCodec

Thanks for your interest in improving the Swift member of the Firechip COBS
family!

## Development

The `CobsCodec` library is pure Swift standard library, so it builds and tests on
Linux as well as macOS:

```console
swift build -c release
swift test
```

To run the shared cross-language conformance vectors locally, point the harness at
a checkout of [firechip/cobs-conformance](https://github.com/firechip/cobs-conformance):

```console
COBS_CONFORMANCE_VECTORS=…/vectors/vectors.jsonl \
COBS_CONFORMANCE_SENTINEL=…/vectors/sentinel.jsonl \
COBS_CONFORMANCE_ERRORS=…/vectors/errors.jsonl \
  swift test --filter Conformance
```

The macOS build is validated in CI on a macOS runner.

## Conventions

- **Conventional Commits** for every commit (`type(scope): subject`), enforced by
  the commit-lint workflow. Allowed types: build, chore, ci, docs, feat, fix,
  perf, refactor, revert, style, test.
- **Trunk-based development** with [`tbdflow`](https://github.com/firechip/tbdflow):
  short-lived branches, frequent merges to `main`.
- The output must stay **byte-identical** to the rest of the family — any codec
  change must still pass the shared conformance vectors.
- Commits and tags are SSH-signed.

## Releases

Releases follow [Semantic Versioning](https://semver.org). Swift Package Manager
resolves versions from Git tags, so a release is a signed `vX.Y.Z` tag pushed to
`main` (plus a `CHANGELOG.md` entry).
