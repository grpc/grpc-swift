# gRPC Swift

This repository contains a gRPC code generator and runtime libraries for Swift.
You can read more about gRPC on the [gRPC project's website][grpcio].

> [!IMPORTANT]  
>  
> See [grpc/grpc-swift-2](https://github.com/grpc/grpc-swift-2) for **gRPC Swift 2**
> which is the current major version of gRPC Swift.

## Versions

This repository contains the code for **gRPC Swift 1** which is now in maintenance 
mode. Only bug fixes and security fixes will be applied. The support window for 
1.x will also decrease over time as new Swift versions are released.

Assuming the next Swift releases are 6.2, 6.3, and 6.4 then the versions of
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
