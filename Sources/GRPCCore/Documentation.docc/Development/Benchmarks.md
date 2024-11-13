# Benchmarks

This article discusses benchmarking in `grpc-swift`.

## Overview

Benchmarks for this package are in a separate Swift Package in the `Performance/Benchmarks`
subdirectory of the repository.

They use the [`package-benchmark`](https://github.com/ordo-one/package-benchmark) plugin.
Benchmarks depends on the [`jemalloc`](https://jemalloc.net) memory allocation library, which is
used by `package-benchmark` to capture memory allocation statistics.

An installation guide can be found in the [Getting Started article](https://swiftpackageindex.com/ordo-one/package-benchmark/documentation/benchmark/gettingstarted)
for `package-benchmark`.

### Running the benchmarks

You can run the benchmarks CLI by going to the `Performance/Benchmarks` subdirectory
(e.g. `cd Performance/Benchmarks`) and invoking:

```
swift package benchmark
```

Profiling benchmarks or building the benchmarks in release mode in Xcode with `jemalloc` isn't
currently supported and requires disabling `jemalloc`.

Make sure you have quit Xcode and then open it from the command line with the `BENCHMARK_DISABLE_JEMALLOC=true`
environment variable set:

```
BENCHMARK_DISABLE_JEMALLOC=true xed .
```

For more information please refer to `swift package benchmark --help` or the [documentation
of `package-benchmark`](https://swiftpackageindex.com/ordo-one/package-benchmark/documentation/benchmark).
