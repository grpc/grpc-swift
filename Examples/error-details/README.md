# Detailed Error

This example demonstrates how to create and unpack detailed errors.

## Overview

A command line tool that demonstrates how a detailed error can be thrown by a
service and unpacked and inspected by a client. The detailed error model is
described in more detailed in the [gRPC Error
Guide](https://grpc.io/docs/guides/error/) and is made available via the
[grpc-swift-protobuf](https://github.com/grpc-swift-protobuf) package.

## Usage

Build and run the example using the CLI:

```console
$ swift run
Error code: resourceExhausted
Error message: The greeter has temporarily run out of greetings.
Error details:
- Localized message (en-GB): Out of enthusiasm. The greeter is having a cup of tea, try again after that.
- Localized message (en-US): Out of enthusiasm. The greeter is taking a coffee break, try again later.
- Help links:
   - https://en.wikipedia.org/wiki/Caffeine (A Wikipedia page about caffeine including its properties and effects.)
```
