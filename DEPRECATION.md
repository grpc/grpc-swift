# gRPC Swift 0.x deprecation

## What is this document?

This document outlines the current plan to deprecate the `0.x` release series of gRPC Swift.

## What is happening?

gRPC Swift versions `v0.x` based on gRPC-Core will soon be replaced with a re-implementation based on [SwiftNIO][nio].

We strongly suggest that new projects use [the re-implementation from the `nio` branch][nio-branch] which we consider to be production ready.

In the coming weeks this branch (currently `master`) containing the `0.x` releases will be renamed `cgrpc`. The `nio` branch containing the [new implementation][nio-branch] will subsequently be renamed to `master` and become the default branch. A `1.0.0` tag will also be created.

Version | Branch Now | Branch After Deprecation
--------|------------|-------------------------
`0.x`   | `master`   | `cgrpc`
`1.x`   | `nio`      | `master`

## What is it being replaced with?

We have rewritten gRPC Swift on top of [SwiftNIO][nio], an open-source asynchronous event-driven networking framework created by Apple. Our implementation will be written in Swift and will not wrap the gRPC Core C library.

## Why is this happening?

There are a number of reasons we have rewritten gRPC Swift:

- The `0.x` releases are built on top of a C interface to the gRPC Core library provided by the [gRPC project][grpc]. This led to a number of memory safety issues and is easy to hold incorrectly.
- Network connectivity changes (e.g. LTE to WiFi, 3G to LTE, etc.) are not handled well by the networking stack in the gRPC Core C library. [Network.framework][network-framework] (where available, see below) alleviates this problem and has integration with [SwiftNIO][nio].
- [SwiftNIO][nio] has gained a lot of traction in the Swift on Server community due to its performance. We believe we can leverage this to improve the performance and stability of gRPC Swift.
- Vendoring copies of the gRPC Core library and BoringSSL is a source of frustration for developers and users.

## What will happen to the `0.x` releases?

We will continue to patch the `cgrpc` branch for security fixes and serious bugs only. There will be no feature development on the `cgrpc` branch and the version of the gRPC Core library will not be updated (unless necessary for a security fix).

## When is this happening?

We plan to deprecate versions `0.x` and tag version `1.0.0` by the end of 2019.

## Which Swift versions will be supported for `1.x`?

Swift 5.0 and later.

## Which platforms will be supported for `1.x`?

We have the same [platform support as SwiftNIO][nio-platforms]. That is:

* macOS 10.12+, iOS 10+
* macOS 10.14+, iOS 12+, or tvOS 12+ (with [Network.framework][network-framework] support via [NIO Transport Services][nio-ts])
* Ubuntu 14.04+

## Which package managers will be supported for `1.x`?

We will provide support for Swift Package Manager as we believe that its integration with Xcode is the most convenient way to manage packages.

CocoaPods support is _not_ currently planned. However, we may provide support if there is significant community interest.

Carthage will _not_ be supported as it has been the source of a [number][carthage0] [of][carthage1] [issues][carthage2] [in][carthage3] [the][carthage4] [past][carthage5].

## Can I try this out now?

Absolutely! Head over to the `nio` [branch][nio-branch] and check out the [quick-start guide][quick-start] or [basic tutorial][basic-tutorial].

## I can't find a feature I used in `0.x`, can you help?

If there’s something you can't find that was in the previous implementation or if anything is unclear then _please_ reach out to us by filing an issue. We also have a [dedicated space in the Swift forums][forums] for the project.


[nio]: https://github.com/apple/swift-nio
[nio-branch]: https://github.com/grpc/grpc-swift/tree/nio
[nio-platforms]: https://github.com/apple/swift-nio#supported-platforms
[nio-ts]: https://github.com/apple/swift-nio-transport-services
[network-framework]: https://developer.apple.com/documentation/network
[grpc]: https://github.com/grpc/grpc
[quick-start]: https://github.com/grpc/grpc-swift/blob/nio/docs/quick-start.md
[basic-tutorial]: https://github.com/grpc/grpc-swift/blob/nio/docs/basic-tutorial.md
[readme]: https://github.com/grpc/grpc-swift/blob/nio/README.md
[forums]: https://forums.swift.org/c/related-projects/grpc-swift
[carthage0]: https://github.com/grpc/grpc-swift/issues/329
[carthage1]: https://github.com/grpc/grpc-swift/issues/449
[carthage2]: https://github.com/grpc/grpc-swift/issues/495
[carthage3]: https://github.com/grpc/grpc-swift/issues/507
[carthage4]: https://github.com/grpc/grpc-swift/issues/604
[carthage5]: https://github.com/grpc/grpc-swift/issues/615
