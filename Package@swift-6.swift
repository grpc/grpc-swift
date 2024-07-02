// swift-tools-version:6.0
/*
 * Copyright 2024, gRPC Authors All rights reserved.
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

// MARK: - Package Dependencies

let packageDependencies: [Package.Dependency] = [
  .package(
    url: "https://github.com/apple/swift-nio.git",
    from: "2.65.0"
  ),
  .package(
    url: "https://github.com/apple/swift-nio-http2.git",
    from: "1.32.0"
  ),
  .package(
    url: "https://github.com/apple/swift-nio-transport-services.git",
    from: "1.15.0"
  ),
  .package(
    url: "https://github.com/apple/swift-nio-extras.git",
    from: "1.4.0"
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
    from: "1.20.2"
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
  .package(
    url: "https://github.com/apple/swift-distributed-tracing.git",
    from: "1.0.0"
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
  static var performanceWorker: Self { .target(name: "performance-worker") }
  static var reflectionService: Self { .target(name: "GRPCReflectionService") }
  static var grpcCodeGen: Self { .target(name: "GRPCCodeGen") }
  static var grpcProtobuf: Self { .target(name: "GRPCProtobuf") }
  static var grpcProtobufCodeGen: Self { .target(name: "GRPCProtobufCodeGen") }

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
  static var dequeModule: Self { .product(name: "DequeModule", package: "swift-collections") }
  static var atomics: Self { .product(name: "Atomics", package: "swift-atomics") }
  static var tracing: Self { .product(name: "Tracing", package: "swift-distributed-tracing") }

  static var grpcCore: Self { .target(name: "GRPCCore") }
  static var grpcInProcessTransport: Self { .target(name: "GRPCInProcessTransport") }
  static var grpcInterceptors: Self { .target(name: "GRPCInterceptors") }
  static var grpcHTTP2Core: Self { .target(name: "GRPCHTTP2Core") }
  static var grpcHTTP2TransportNIOPosix: Self { .target(name: "GRPCHTTP2TransportNIOPosix") }
  static var grpcHTTP2TransportNIOTransportServices: Self { .target(name: "GRPCHTTP2TransportNIOTransportServices") }
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
      ].appending(
        .nioSSL, if: includeNIOSSL
      ),
      path: "Sources/GRPC",
      swiftSettings: [.swiftLanguageVersion(.v5)]
    )
  }

  static var grpcCore: Target {
    .target(
      name: "GRPCCore",
      dependencies: [
        .dequeModule,
        .atomics
      ],
      path: "Sources/GRPCCore",
      swiftSettings: [.swiftLanguageVersion(.v5)]
    )
  }

  static var grpcInProcessTransport: Target {
    .target(
      name: "GRPCInProcessTransport",
      dependencies: [
        .grpcCore
      ],
      swiftSettings: [.swiftLanguageVersion(.v6)]
    )
  }

  static var grpcInterceptors: Target {
    .target(
      name: "GRPCInterceptors",
      dependencies: [
        .grpcCore,
        .tracing
      ],
      swiftSettings: [.swiftLanguageVersion(.v6)]
    )
  }

  static var grpcHTTP2Core: Target {
    .target(
      name: "GRPCHTTP2Core",
      dependencies: [
        .grpcCore,
        .nioCore,
        .nioHTTP2,
        .cgrpcZlib,
        .dequeModule,
        .atomics
      ],
      swiftSettings: [.swiftLanguageVersion(.v6)]
    )
  }

  static var grpcHTTP2TransportNIOPosix: Target {
    .target(
      name: "GRPCHTTP2TransportNIOPosix",
      dependencies: [
        .grpcCore,
        .grpcHTTP2Core,
        .nioPosix,
        .nioExtras
      ],
      swiftSettings: [.swiftLanguageVersion(.v6)]
    )
  }

  static var grpcHTTP2TransportNIOTransportServices: Target {
    .target(
      name: "GRPCHTTP2TransportNIOTransportServices",
      dependencies: [
        .grpcCore,
        .grpcHTTP2Core,
        .nioCore,
        .nioExtras,
        .nioTransportServices
      ],
      swiftSettings: [.swiftLanguageVersion(.v6)]
    )
  }

  static var cgrpcZlib: Target {
    .target(
      name: cgrpcZlibTargetName,
      path: "Sources/CGRPCZlib",
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
        .grpcCodeGen,
        .grpcProtobufCodeGen
      ],
      exclude: [
        "README.md",
      ],
      swiftSettings: [.swiftLanguageVersion(.v5)]
    )
  }

  static var performanceWorker: Target {
    .executableTarget(
      name: "performance-worker",
      dependencies: [
        .grpcCore,
        .grpcHTTP2Core,
        .grpcHTTP2TransportNIOPosix,
        .grpcProtobuf,
        .nioCore,
        .nioFileSystem,
        .argumentParser
      ],
      swiftSettings: [.swiftLanguageVersion(.v6)]
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
        .reflectionService
      ].appending(
        .nioSSL, if: includeNIOSSL
      ),
      exclude: [
        "Codegen/Serialization/echo.grpc.reflection"
      ],
      swiftSettings: [.swiftLanguageVersion(.v5)]
    )
  }

  static var grpcCoreTests: Target {
    .testTarget(
      name: "GRPCCoreTests",
      dependencies: [
        .grpcCore,
        .grpcInProcessTransport,
        .dequeModule,
        .atomics,
        .protobuf,
      ],
      swiftSettings: [.swiftLanguageVersion(.v5)]
    )
  }

  static var grpcInProcessTransportTests: Target {
    .testTarget(
      name: "GRPCInProcessTransportTests",
      dependencies: [
        .grpcCore,
        .grpcInProcessTransport
      ],
      swiftSettings: [.swiftLanguageVersion(.v5)]
    )
  }

  static var grpcInterceptorsTests: Target {
    .testTarget(
      name: "GRPCInterceptorsTests",
      dependencies: [
        .grpcCore,
        .tracing,
        .nioCore,
        .grpcInterceptors
      ],
      swiftSettings: [.swiftLanguageVersion(.v5)]
    )
  }

  static var grpcHTTP2CoreTests: Target {
    .testTarget(
      name: "GRPCHTTP2CoreTests",
      dependencies: [
        .grpcHTTP2Core,
        .nioCore,
        .nioHTTP2,
        .nioEmbedded,
        .nioTestUtils,
      ],
      swiftSettings: [.swiftLanguageVersion(.v5)]
    )
  }

  static var grpcHTTP2TransportTests: Target {
    .testTarget(
      name: "GRPCHTTP2TransportTests",
      dependencies: [
        .grpcHTTP2Core,
        .grpcHTTP2TransportNIOPosix,
        .grpcHTTP2TransportNIOTransportServices,
        .grpcProtobuf
      ],
      swiftSettings: [.swiftLanguageVersion(.v5)]
    )
  }

  static var grpcCodeGenTests: Target {
    .testTarget(
      name: "GRPCCodeGenTests",
      dependencies: [
        .grpcCodeGen
      ],
      swiftSettings: [.swiftLanguageVersion(.v5)]
    )
  }

  static var grpcProtobufTests: Target {
    .testTarget(
      name: "GRPCProtobufTests",
      dependencies: [
        .grpcProtobuf,
        .grpcCore,
        .protobuf
      ],
      swiftSettings: [.swiftLanguageVersion(.v6)]
    )
  }

  static var grpcProtobufCodeGenTests: Target {
    .testTarget(
      name: "GRPCProtobufCodeGenTests",
      dependencies: [
        .grpcCodeGen,
        .grpcProtobufCodeGen,
        .protobuf,
        .protobufPluginLibrary
      ],
      swiftSettings: [.swiftLanguageVersion(.v6)]
    )
  }

  static var inProcessInteroperabilityTests: Target {
    .testTarget(
      name: "InProcessInteroperabilityTests",
      dependencies: [
        .grpcInProcessTransport,
        .interoperabilityTests,
        .grpcCore
      ],
      swiftSettings: [.swiftLanguageVersion(.v5)]
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
      swiftSettings: [.swiftLanguageVersion(.v5)]
    )
  }

  static var interoperabilityTestImplementation: Target {
    .target(
      name: "InteroperabilityTests",
      dependencies: [
        .grpcCore,
        .grpcProtobuf
      ],
      swiftSettings: [.swiftLanguageVersion(.v5)]
    )
  }

  static var interoperabilityTestsExecutable: Target {
    .executableTarget(
      name: "interoperability-tests",
      dependencies: [
        .grpcCore,
        .grpcHTTP2Core,
        .grpcHTTP2TransportNIOPosix,
        .interoperabilityTests,
        .argumentParser
      ],
      swiftSettings: [.swiftLanguageVersion(.v6)]
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
      swiftSettings: [.swiftLanguageVersion(.v5)]
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
      swiftSettings: [.swiftLanguageVersion(.v5)]
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
      swiftSettings: [.swiftLanguageVersion(.v5)]
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
      swiftSettings: [.swiftLanguageVersion(.v5)]
    )
  }

  static var grpcSampleData: Target {
    .target(
      name: "GRPCSampleData",
      dependencies: includeNIOSSL ? [.nioSSL] : [],
      exclude: [
        "bundle.p12",
      ],
      swiftSettings: [.swiftLanguageVersion(.v5)]
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
      path: "Sources/Examples/v1/Echo/Model",
      swiftSettings: [.swiftLanguageVersion(.v5)]
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
      path: "Sources/Examples/v1/Echo/Implementation",
      swiftSettings: [.swiftLanguageVersion(.v5)]
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
      path: "Sources/Examples/v1/Echo/Runtime",
      swiftSettings: [.swiftLanguageVersion(.v5)]
    )
  }

  static var echo_v2: Target {
    .executableTarget(
      name: "echo-v2",
      dependencies: [
        .grpcCore,
        .grpcProtobuf,
        .grpcHTTP2Core,
        .grpcHTTP2TransportNIOPosix,
        .argumentParser,
      ].appending(
        .nioSSL, if: includeNIOSSL
      ),
      path: "Sources/Examples/v2/Echo",
      swiftSettings: [.swiftLanguageVersion(.v6), .enableUpcomingFeature("ExistentialAny")]
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
      path: "Sources/Examples/v1/HelloWorld/Model",
      swiftSettings: [.swiftLanguageVersion(.v5)]
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
      path: "Sources/Examples/v1/HelloWorld/Client",
      swiftSettings: [.swiftLanguageVersion(.v5)]
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
      path: "Sources/Examples/v1/HelloWorld/Server",
      swiftSettings: [.swiftLanguageVersion(.v5)]
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
      path: "Sources/Examples/v1/RouteGuide/Model",
      swiftSettings: [.swiftLanguageVersion(.v5)]
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
      path: "Sources/Examples/v1/RouteGuide/Client",
      swiftSettings: [.swiftLanguageVersion(.v5)]
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
      path: "Sources/Examples/v1/RouteGuide/Server",
      swiftSettings: [.swiftLanguageVersion(.v5)]
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
      path: "Sources/Examples/v1/PacketCapture",
      exclude: [
        "README.md",
      ],
      swiftSettings: [.swiftLanguageVersion(.v5)]
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
      swiftSettings: [.swiftLanguageVersion(.v5)]
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
      path: "Sources/Examples/v1/ReflectionService",
      resources: [
        .copy("Generated")
      ],
      swiftSettings: [.swiftLanguageVersion(.v5)]
    )
  }

  static var grpcCodeGen: Target {
    .target(
      name: "GRPCCodeGen",
      path: "Sources/GRPCCodeGen",
      swiftSettings: [.swiftLanguageVersion(.v6)]
    )
  }

  static var grpcProtobuf: Target {
    .target(
      name: "GRPCProtobuf",
      dependencies: [
        .grpcCore,
        .protobuf,
      ],
      path: "Sources/GRPCProtobuf",
      swiftSettings: [.swiftLanguageVersion(.v6)]
    )
  }

  static var grpcProtobufCodeGen: Target {
    .target(
      name: "GRPCProtobufCodeGen",
      dependencies: [
        .protobuf,
        .protobufPluginLibrary,
        .grpcCodeGen
      ],
      path: "Sources/GRPCProtobufCodeGen",
      swiftSettings: [.swiftLanguageVersion(.v6)]
    )
  }

  static var grpcHealth: Target {
    .target(
      name: "GRPCHealth",
      dependencies: [
        .grpcCore,
        .grpcProtobuf
      ],
      path: "Sources/Services/Health",
      swiftSettings: [.swiftLanguageVersion(.v6)]
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

  static var _grpcCore: Product {
    .library(
      name: "_GRPCCore",
      targets: ["GRPCCore"]
    )
  }

  static var _grpcProtobuf: Product {
    .library(
      name: "_GRPCProtobuf",
      targets: ["GRPCProtobuf"]
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
    // v1
    .grpc,
    .cgrpcZlib,
    .grpcReflectionService,
    .protocGenGRPCSwift,
    .grpcSwiftPlugin,
    // v2
    ._grpcCore,
    ._grpcProtobuf,
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

    // v2
    .grpcCore,
    .grpcInProcessTransport,
    .grpcCodeGen,
    .grpcInterceptors,
    .grpcHTTP2Core,
    .grpcHTTP2TransportNIOPosix,
    .grpcHTTP2TransportNIOTransportServices,
    .grpcProtobuf,
    .grpcProtobufCodeGen,
    .grpcHealth,
    .interoperabilityTestImplementation,
    .interoperabilityTestsExecutable,
    .performanceWorker,

    // v2 tests
    .grpcCoreTests,
    .grpcInProcessTransportTests,
    .grpcCodeGenTests,
    .grpcInterceptorsTests,
    .grpcHTTP2CoreTests,
    .grpcHTTP2TransportTests,
    .grpcProtobufTests,
    .grpcProtobufCodeGenTests,
    .inProcessInteroperabilityTests,

    // v2 examples
    .echo_v2,
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
