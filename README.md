# gRPC Swift

This repository contains a gRPC code generator and runtime libraries for Swift.
You can read more about gRPC on the [gRPC project's website][grpcio].

## Versions

gRPC Swift is currently undergoing active development to take full advantage of
Swift's native concurrency features. The culmination of this work will be a new
major version, v2.x. Pre-release versions will be available in the near future.

In the meantime, v1.x is available and still supported. You can read more about
it on the [Swift Package Index][spi-grpc-swift-main].

## Support

As gRPC Swift v2.x is being developed, v1.x will continue to be supported.
However, the support window for v1.x will decrease over time as new Swift
versions are released.

From the next Swift release, the number of Swift versions supported by
gRPC Swift v1.x will decrease by one each time.

Assuming the next Swift releases are 6.1, 6.2, 6.3, and 6.4 then the versions of
Swift supported by gRPC Swift are as follows.

Swift Release | Swift versions supported by 1.x
--------------|--------------------------------
6.1           | 5.10, 6.0, 6.1
6.2           | 6.1, 6.2
6.3           | 6.3
6.4           | Unsupported

## Security

Please see [SECURITY.md](SECURITY.md).

## License

gRPC Swift is released under the same license as [gRPC][gh-grpc], repeated in
[LICENSE](LICENSE).

## Contributing

Please get involved! See our [guidelines for contributing](CONTRIBUTING.md).

[gh-grpc]: https://github.com/grpc/grpc
[grpcio]: https://grpc.io
[spi-grpc-swift-main]: https://swiftpackageindex.com/grpc/grpc-swift/main/documentation/grpccore
