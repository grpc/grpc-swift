# gRPC Connection Backoff Interoperability Test

This module implements the gRPC connection backoff interoperability test as
described in the [specification][interop-test].

## Running the Test

The C++ interoperability test server implements the required server and should
be targeted when running this test. It is available in the main [gRPC
repository][grpc-repo] and may be built using `bazel` (`bazel build
test/cpp/interop:reconnect_interop_server`) or one of the other options for
[building the C++ source][grpc-cpp-build].

1. Start the server: `./path/to/server --control_port=8080 --retry_port=8081`
1. Start the test: `swift run ConnectionBackoffInteropTestRunner 8080 8081`

The test takes **approximately 10 minutes to complete** and logs are written to
`stderr`.

[interop-test]: https://github.com/grpc/grpc/blob/master/doc/connection-backoff-interop-test-description.md
[grpc-cpp-build]: https://github.com/grpc/grpc/blob/master/BUILDING.md
[grpc-repo]: https://github.com/grpc/grpc.git
