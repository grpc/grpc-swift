# gRPC Swift: Fuzz Testing

This package contains binaries for running fuzz testing.

## Building

Building the binary requires additional arguments be passed to the Swift
compiler:

```
swift build \
  -Xswiftc -sanitize=fuzzer,address \
  -Xswiftc -parse-as-library
```

Note also that on macOS the Swift toolchain shipped with Xcode _does not_
currently include fuzzing support and one must use a toolchain
from [swift.org](https://swift.org/download/). Building on macOS therefore
requires the above command be run via `xcrun`:

```
xcrun --toolchain swift \
  swift build \
    -Xswiftc -sanitize=fuzzer,address \
    -Xswiftc -parse-as-library
```

## Failures

The `FailCases` directory contains fuzzing test input which previously caused
failures in gRPC.
