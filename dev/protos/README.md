# Protos

This directory contains proto messages used by gRPC Swift. These are split
across different directories:

- `upstream` contains `.proto` files pulled from upstream sources. You can
  update them using `fetch.sh`. Note that doing so will replace `upstream` in
  its entirety.
- `examples` contains `.proto` files used in common examples.
- `tests` contains `.proto` files used  in tests.

You can run `generate.sh` to re-generate all files generated using `protoc` with
the Swift and gRPC Swift plugins.
