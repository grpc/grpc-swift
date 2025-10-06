// swift-tools-version: 6.1
/*
 * Copyright 2017, gRPC Authors All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import PackageDescription
// swiftformat puts the next import before the tools version.
// swiftformat:disable:next sortImports
import class Foundation.ProcessInfo

let grpcPackageName = "grpc-swift"
let grpcProductName = "GRPC"
let cgrpcZlibProductName = "CGRPCZlib"
let grpcTargetName = grpcProductName
let cgrpcZlibTargetName = cgrpcZlibProductName

let includeNIOSSL = ProcessInfo.processInfo.environment["GRPC_NO_NIO_SSL"] == nil
let defaultSwiftSettings: [SwiftSetting] = [.swiftLanguageMode(.v5)]

// MARK: - Package Dependencies

let packageDependencies: [Package.Dependency] = [
  .package(
    url: "https://github.com/apple/swift-nio.git",
    from: "2.65.0"
  ),
  .package(
    url: "https://github.com/apple/swift-nio-http2.git",
    from: "1.36.0"
  ),
  .package(
    url: "https://github.com/apple/swift-nio-transport-services.git",
    from: "1.24.0"
  ),
  .package(
    url: "https://github.com/apple/swift-nio-extras.git",
    from: "1.24.0"
  ),
  .package(
    url: "https://github.com/apple/swift-collections.git",
    from: "1.0.5"
  ),
  .package(
    url: "https://github.com/apple/swift-atomics.git",
    from: "1.2.0"
  ),
  .package(
    url: "https://github.com/apple/swift-protobuf.git",
    from: "1.31.0"
  ),
  .package(
    url: "https://github.com/apple/swift-log.git",
    from: "1.4.4"
  ),
  .package(
    url: "https://github.com/apple/swift-argument-parser.git",
    // Version is higher than in other Package@swift manifests: 1.1.0 raised the minimum Swift
    // version and indluded async support.
    from: "1.1.1"
  ),
].appending(
  .package(
    url: "https://github.com/apple/swift-nio-ssl.git",
    from: "2.23.0"
  ),
  if: includeNIOSSL
)

// MARK: - Target Dependencies

extension Target.Dependency {
  // Target dependencies; external
  static var grpc: Self { .target(name: grpcTargetName) }
  static var cgrpcZlib: Self { .target(name: cgrpcZlibTargetName) }
  static var protocGenGRPCSwift: Self { .target(name: "protoc-gen-grpc-swift") }
  static var reflectionService: Self { .target(name: "GRPCReflectionService") }

  // Target dependencies; internal
  static var grpcSampleData: Self { .target(name: "GRPCSampleData") }
  static var echoModel: Self { .target(name: "EchoModel") }
  static var echoImplementation: Self { .target(name: "EchoImplementation") }
  static var helloWorldModel: Self { .target(name: "HelloWorldModel") }
  static var routeGuideModel: Self { .target(name: "RouteGuideModel") }
  static var interopTestModels: Self { .target(name: "GRPCInteroperabilityTestModels") }
  static var interopTestImplementation: Self {
    .target(name: "GRPCInteroperabilityTestsImplementation")
  }
  static var interoperabilityTests: Self { .target(name: "InteroperabilityTests") }

  // Product dependencies
  static var argumentParser: Self {
    .product(
      name: "ArgumentParser",
      package: "swift-argument-parser"
    )
  }
  static var nio: Self { .product(name: "NIO", package: "swift-nio") }
  static var nioConcurrencyHelpers: Self {
    .product(
      name: "NIOConcurrencyHelpers",
      package: "swift-nio"
    )
  }
  static var nioCore: Self { .product(name: "NIOCore", package: "swift-nio") }
  static var nioEmbedded: Self { .product(name: "NIOEmbedded", package: "swift-nio") }
  static var nioExtras: Self { .product(name: "NIOExtras", package: "swift-nio-extras") }
  static var nioFoundationCompat: Self { .product(name: "NIOFoundationCompat", package: "swift-nio") }
  static var nioHTTP1: Self { .product(name: "NIOHTTP1", package: "swift-nio") }
  static var nioHTTP2: Self { .product(name: "NIOHTTP2", package: "swift-nio-http2") }
  static var nioPosix: Self { .product(name: "NIOPosix", package: "swift-nio") }
  static var nioSSL: Self { .product(name: "NIOSSL", package: "swift-nio-ssl") }
  static var nioTLS: Self { .product(name: "NIOTLS", package: "swift-nio") }
  static var nioTransportServices: Self {
    .product(
      name: "NIOTransportServices",
      package: "swift-nio-transport-services"
    )
  }
  static var nioTestUtils: Self { .product(name: "NIOTestUtils", package: "swift-nio") }
  static var nioFileSystem: Self { .product(name: "_NIOFileSystem", package: "swift-nio") }
  static var logging: Self { .product(name: "Logging", package: "swift-log") }
  static var protobuf: Self { .product(name: "SwiftProtobuf", package: "swift-protobuf") }
  static var protobufPluginLibrary: Self {
    .product(
      name: "SwiftProtobufPluginLibrary",
      package: "swift-protobuf"
    )
  }
  static var atomics: Self { .product(name: "Atomics", package: "swift-atomics") }
  static var dequeModule: Self { .product(name: "DequeModule", package: "swift-collections") }
}

// MARK: - Targets

extension Target {
  static var grpc: Target {
    .target(
      name: grpcTargetName,
      dependencies: [
        .cgrpcZlib,
        .nio,
        .nioCore,
        .nioPosix,
        .nioEmbedded,
        .nioFoundationCompat,
        .nioTLS,
        .nioTransportServices,
        .nioHTTP1,
        .nioHTTP2,
        .nioExtras,
        .logging,
        .protobuf,
        .dequeModule,
        .atomics
      ].appending(
        .nioSSL, if: includeNIOSSL
      ),
      path: "Sources/GRPC",
      swiftSettings: defaultSwiftSettings
    )
  }

  static var cgrpcZlib: Target {
    .target(
      name: cgrpcZlibTargetName,
      path: "Sources/CGRPCZlib",
      swiftSettings: defaultSwiftSettings,
      linkerSettings: [
        .linkedLibrary("z"),
      ]
    )
  }

  static var protocGenGRPCSwift: Target {
    .executableTarget(
      name: "protoc-gen-grpc-swift",
      dependencies: [
        .protobuf,
        .protobufPluginLibrary,
      ],
      exclude: [
        "README.md",
      ],
      swiftSettings: defaultSwiftSettings
    )
  }

  static var grpcSwiftPlugin: Target {
    .plugin(
      name: "GRPCSwiftPlugin",
      capability: .buildTool(),
      dependencies: [
        .protocGenGRPCSwift,
      ]
    )
  }

  static var grpcTests: Target {
    .testTarget(
      name: "GRPCTests",
      dependencies: [
        .grpc,
        .echoModel,
        .echoImplementation,
        .helloWorldModel,
        .interopTestModels,
        .interopTestImplementation,
        .grpcSampleData,
        .nioCore,
        .nioConcurrencyHelpers,
        .nioPosix,
        .nioTLS,
        .nioHTTP1,
        .nioHTTP2,
        .nioEmbedded,
        .nioTransportServices,
        .logging,
        .reflectionService,
        .atomics
      ].appending(
        .nioSSL, if: includeNIOSSL
      ),
      exclude: [
        "Codegen/Serialization/echo.grpc.reflection"
      ],
      swiftSettings: defaultSwiftSettings,
    )
  }

  static var interopTestModels: Target {
    .target(
      name: "GRPCInteroperabilityTestModels",
      dependencies: [
        .grpc,
        .nio,
        .protobuf,
      ],
      exclude: [
        "README.md",
        "generate.sh",
        "src/proto/grpc/testing/empty.proto",
        "src/proto/grpc/testing/empty_service.proto",
        "src/proto/grpc/testing/messages.proto",
        "src/proto/grpc/testing/test.proto",
        "unimplemented_call.patch",
      ],
      swiftSettings: defaultSwiftSettings
    )
  }

  static var interopTestImplementation: Target {
    .target(
      name: "GRPCInteroperabilityTestsImplementation",
      dependencies: [
        .grpc,
        .interopTestModels,
        .nioCore,
        .nioPosix,
        .nioHTTP1,
        .logging,
      ].appending(
        .nioSSL, if: includeNIOSSL
      ),
      swiftSettings: defaultSwiftSettings
    )
  }

  static var interopTests: Target {
    .executableTarget(
      name: "GRPCInteroperabilityTests",
      dependencies: [
        .grpc,
        .interopTestImplementation,
        .nioCore,
        .nioPosix,
        .logging,
        .argumentParser,
      ],
      swiftSettings: defaultSwiftSettings
    )
  }

  static var backoffInteropTest: Target {
    .executableTarget(
      name: "GRPCConnectionBackoffInteropTest",
      dependencies: [
        .grpc,
        .interopTestModels,
        .nioCore,
        .nioPosix,
        .logging,
        .argumentParser,
      ],
      exclude: [
        "README.md",
      ],
      swiftSettings: defaultSwiftSettings
    )
  }

  static var perfTests: Target {
    .executableTarget(
      name: "GRPCPerformanceTests",
      dependencies: [
        .grpc,
        .grpcSampleData,
        .nioCore,
        .nioEmbedded,
        .nioPosix,
        .nioHTTP2,
        .argumentParser,
      ],
      swiftSettings: defaultSwiftSettings
    )
  }

  static var grpcSampleData: Target {
    .target(
      name: "GRPCSampleData",
      dependencies: includeNIOSSL ? [.nioSSL] : [],
      exclude: [
        "bundle.p12",
      ],
      swiftSettings: defaultSwiftSettings
    )
  }

  static var echoModel: Target {
    .target(
      name: "EchoModel",
      dependencies: [
        .grpc,
        .nio,
        .protobuf,
      ],
      path: "Examples/v1/Echo/Model",
      swiftSettings: defaultSwiftSettings
    )
  }

  static var echoImplementation: Target {
    .target(
      name: "EchoImplementation",
      dependencies: [
        .echoModel,
        .grpc,
        .nioCore,
        .nioHTTP2,
        .protobuf,
      ],
      path: "Examples/v1/Echo/Implementation",
      swiftSettings: defaultSwiftSettings
    )
  }

  static var echo: Target {
    .executableTarget(
      name: "Echo",
      dependencies: [
        .grpc,
        .echoModel,
        .echoImplementation,
        .grpcSampleData,
        .nioCore,
        .nioPosix,
        .logging,
        .argumentParser,
      ].appending(
        .nioSSL, if: includeNIOSSL
      ),
      path: "Examples/v1/Echo/Runtime",
      swiftSettings: defaultSwiftSettings
    )
  }

  static var helloWorldModel: Target {
    .target(
      name: "HelloWorldModel",
      dependencies: [
        .grpc,
        .nio,
        .protobuf,
      ],
      path: "Examples/v1/HelloWorld/Model",
      swiftSettings: defaultSwiftSettings
    )
  }

  static var helloWorldClient: Target {
    .executableTarget(
      name: "HelloWorldClient",
      dependencies: [
        .grpc,
        .helloWorldModel,
        .nioCore,
        .nioPosix,
        .argumentParser,
      ],
      path: "Examples/v1/HelloWorld/Client",
      swiftSettings: defaultSwiftSettings
    )
  }

  static var helloWorldServer: Target {
    .executableTarget(
      name: "HelloWorldServer",
      dependencies: [
        .grpc,
        .helloWorldModel,
        .nioCore,
        .nioPosix,
        .argumentParser,
      ],
      path: "Examples/v1/HelloWorld/Server",
      swiftSettings: defaultSwiftSettings
    )
  }

  static var routeGuideModel: Target {
    .target(
      name: "RouteGuideModel",
      dependencies: [
        .grpc,
        .nio,
        .protobuf,
      ],
      path: "Examples/v1/RouteGuide/Model",
      swiftSettings: defaultSwiftSettings
    )
  }

  static var routeGuideClient: Target {
    .executableTarget(
      name: "RouteGuideClient",
      dependencies: [
        .grpc,
        .routeGuideModel,
        .nioCore,
        .nioPosix,
        .argumentParser,
      ],
      path: "Examples/v1/RouteGuide/Client",
      swiftSettings: defaultSwiftSettings
    )
  }

  static var routeGuideServer: Target {
    .executableTarget(
      name: "RouteGuideServer",
      dependencies: [
        .grpc,
        .routeGuideModel,
        .nioCore,
        .nioConcurrencyHelpers,
        .nioPosix,
        .argumentParser,
      ],
      path: "Examples/v1/RouteGuide/Server",
      swiftSettings: defaultSwiftSettings
    )
  }

  static var packetCapture: Target {
    .executableTarget(
      name: "PacketCapture",
      dependencies: [
        .grpc,
        .echoModel,
        .nioCore,
        .nioPosix,
        .nioExtras,
        .argumentParser,
      ],
      path: "Examples/v1/PacketCapture",
      exclude: [
        "README.md",
      ],
      swiftSettings: defaultSwiftSettings
    )
  }

  static var reflectionService: Target {
    .target(
      name: "GRPCReflectionService",
      dependencies: [
        .grpc,
        .nio,
        .protobuf,
      ],
      path: "Sources/GRPCReflectionService",
      swiftSettings: defaultSwiftSettings
    )
  }

  static var reflectionServer: Target {
    .executableTarget(
      name: "ReflectionServer",
      dependencies: [
        .grpc,
        .reflectionService,
        .helloWorldModel,
        .nioCore,
        .nioPosix,
        .argumentParser,
        .echoModel,
        .echoImplementation
      ],
      path: "Examples/v1/ReflectionService",
      resources: [
        .copy("Generated")
      ],
      swiftSettings: defaultSwiftSettings
    )
  }
}

// MARK: - Products

extension Product {
  static var grpc: Product {
    .library(
      name: grpcProductName,
      targets: [grpcTargetName]
    )
  }

  static var cgrpcZlib: Product {
    .library(
      name: cgrpcZlibProductName,
      targets: [cgrpcZlibTargetName]
    )
  }

  static var grpcReflectionService: Product {
    .library(
      name: "GRPCReflectionService",
      targets: ["GRPCReflectionService"]
    )
  }

  static var protocGenGRPCSwift: Product {
    .executable(
      name: "protoc-gen-grpc-swift",
      targets: ["protoc-gen-grpc-swift"]
    )
  }

  static var grpcSwiftPlugin: Product {
    .plugin(
      name: "GRPCSwiftPlugin",
      targets: ["GRPCSwiftPlugin"]
    )
  }
}

// MARK: - Package

let package = Package(
  name: grpcPackageName,
  products: [
    .grpc,
    .cgrpcZlib,
    .grpcReflectionService,
    .protocGenGRPCSwift,
    .grpcSwiftPlugin,
  ],
  dependencies: packageDependencies,
  targets: [
    // Products
    .grpc,
    .cgrpcZlib,
    .protocGenGRPCSwift,
    .grpcSwiftPlugin,
    .reflectionService,

    // Tests etc.
    .grpcTests,
    .interopTestModels,
    .interopTestImplementation,
    .interopTests,
    .backoffInteropTest,
    .perfTests,
    .grpcSampleData,

    // Examples
    .echoModel,
    .echoImplementation,
    .echo,
    .helloWorldModel,
    .helloWorldClient,
    .helloWorldServer,
    .routeGuideModel,
    .routeGuideClient,
    .routeGuideServer,
    .packetCapture,
    .reflectionServer,
  ]
)

extension Array {
  func appending(_ element: Element, if condition: Bool) -> [Element] {
    if condition {
      return self + [element]
    } else {
      return self
    }
  }
}
