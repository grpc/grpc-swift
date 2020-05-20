# `protoc-gen-grpc-swift` Tests

This directory contains tests for the `protoc-gen-grpc-swift` plugin.

Each test runs `protoc` with the `protoc-gen-grpc-swift` plugin with input
`.proto` files and compares the generated output to "good" output files. Each
test directory must contain the following files/directories:

- `proto/` a directory containing the input `.proto` files
- `golden/` a directory containing the good generated code
- `generate-and-diff.sh` for generating and diffing the generated files against
  the golden output

The tests also require that the absolute path of the plugin is set in the
`PROTOC_GEN_GRPC_SWIFT` environment variable.

## Running the Tests

All Tests can be run by invoking:

```bash
./run-tests.sh
```

Individual tests can be run by invoking the `generate-and-diff.sh` script in
the relevant test directory:

```bash
./01-echo/generate-and-diff.sh
```
