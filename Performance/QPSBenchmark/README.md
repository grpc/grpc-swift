#  QPS Benchmark worker

An implementation of the QPS worker for benchmarking described in the
[gRPC benchmarking guide](https://grpc.io/docs/guides/benchmarking/)

## Building

To rebuild the proto files run `make generate-qps-worker`.

The benchmarks can be built in the usual Swift Package Manager way but release
mode is strongly recommended: `swift build -c release`

## Running the benchmarks

To date the changes to gRPC to run the tests automatically have not been pushed
upstream. You can easily run the tests locally using the C++ driver program.

This can be built using Bazel from the root of a checkout of the
[grpc/grpc](https://github.com/grpc/grpc) repository with:

```sh
bazel build test/cpp/qps:qps_json_driver
```

The `qps_json_driver` binary will be in `bazel-bin/test/cpp/qps/`.

For examples of running benchmarking tests proceed as follows.

> **Note:** the driver may also be built (via CMake) as a side effect of
> running the performance testing script (`./tools/run_tests/run_performance_tests.py`)
> from [grpc/grpc](https://github.com/grpc/grpc).
>
> The script is also the source of the scenarios listed below.

### Setting Up the Environment

1. Open a terminal window and run the QPSBenchmark, this will become the server when instructed by the driver.

   ```sh
   swift run -c release QPSBenchmark --driver_port 10400
   ```


2. Open another terminal window and run QPSBenchmark, this will become the client when instructed by the driver.

   ```sh
   swift run -c release QPSBenchmark --driver_port 10410
   ```

3. Configure the environment for the driver:

   ```sh
   export QPS_WORKERS="localhost:10400,localhost:10410"
   ```

4. Invoke the driver with a scenario file, for example:

   ```sh
   /path/to/qps_json_driver --scenarios_file=/path/to/scenario.json
   ```

### Scenarios

- `scenarios/unary-unconstrained.json`: will run a test with unary RPCs
  using all cores on the machine. 64 clients will connect to the server, each
  enqueuing up to 100 requests.
- `scenarios/unary-1-connection.json`: as above with a single client.
- `scenarios/bidirectional-ping-pong-1-connection.json`: will run bidirectional
  streaming RPCs using a single client.
