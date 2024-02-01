// swift-tools-version:5.7
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

// MARK: - Package Dependencies

let packageDependencies: [Package.Dependency] = [
  .package(
    url: "https://github.com/apple/swift-nio.git",
    from: "2.58.0"
  ),
  .package(
    url: "https://github.com/apple/swift-nio-http2.git",
    from: "1.24.1"
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
    url: "https://github.com/apple/swift-docc-plugin",
    from: "1.0.0"
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
  static let grpc: Self = .target(name: grpcTargetName)
  static let cgrpcZlib: Self = .target(name: cgrpcZlibTargetName)
  static let protocGenGRPCSwift: Self = .target(name: "protoc-gen-grpc-swift")
  static let reflectionService: Self = .target(name: "GRPCReflectionService")
  static let grpcCodeGen: Self = .target(name: "GRPCCodeGen")
  static let grpcProtobuf: Self = .target(name: "GRPCProtobuf")
  static let grpcProtobufCodeGen: Self = .target(name: "GRPCProtobufCodeGen")

  // Target dependencies; internal
  static let grpcSampleData: Self = .target(name: "GRPCSampleData")
  static let echoModel: Self = .target(name: "EchoModel")
  static let echoImplementation: Self = .target(name: "EchoImplementation")
  static let helloWorldModel: Self = .target(name: "HelloWorldModel")
  static let routeGuideModel: Self = .target(name: "RouteGuideModel")
  static let interopTestModels: Self = .target(name: "GRPCInteroperabilityTestModels")
  static let interopTestImplementation: Self =
    .target(name: "GRPCInteroperabilityTestsImplementation")

  // Product dependencies
  static let argumentParser: Self = .product(
    name: "ArgumentParser",
    package: "swift-argument-parser"
  )
  static let nio: Self = .product(name: "NIO", package: "swift-nio")
  static let nioConcurrencyHelpers: Self = .product(
    name: "NIOConcurrencyHelpers",
    package: "swift-nio"
  )
  static let nioCore: Self = .product(name: "NIOCore", package: "swift-nio")
  static let nioEmbedded: Self = .product(name: "NIOEmbedded", package: "swift-nio")
  static let nioExtras: Self = .product(name: "NIOExtras", package: "swift-nio-extras")
  static let nioFoundationCompat: Self = .product(name: "NIOFoundationCompat", package: "swift-nio")
  static let nioHTTP1: Self = .product(name: "NIOHTTP1", package: "swift-nio")
  static let nioHTTP2: Self = .product(name: "NIOHTTP2", package: "swift-nio-http2")
  static let nioPosix: Self = .product(name: "NIOPosix", package: "swift-nio")
  static let nioSSL: Self = .product(name: "NIOSSL", package: "swift-nio-ssl")
  static let nioTLS: Self = .product(name: "NIOTLS", package: "swift-nio")
  static let nioTransportServices: Self = .product(
    name: "NIOTransportServices",
    package: "swift-nio-transport-services"
  )
  static let nioTestUtils: Self = .product(name: "NIOTestUtils", package: "swift-nio")
  static let logging: Self = .product(name: "Logging", package: "swift-log")
  static let protobuf: Self = .product(name: "SwiftProtobuf", package: "swift-protobuf")
  static let protobufPluginLibrary: Self = .product(
    name: "SwiftProtobufPluginLibrary",
    package: "swift-protobuf"
  )
  static let dequeModule: Self = .product(name: "DequeModule", package: "swift-collections")
  static let atomics: Self = .product(name: "Atomics", package: "swift-atomics")
  static let tracing: Self = .product(name: "Tracing", package: "swift-distributed-tracing")

  static let grpcCore: Self = .target(name: "GRPCCore")
  static let grpcInProcessTransport: Self = .target(name: "GRPCInProcessTransport")
  static let grpcInterceptors: Self = .target(name: "GRPCInterceptors")
  static let grpcHTTP2Core: Self = .target(name: "GRPCHTTP2Core")
  static let grpcHTTP2TransportNIOPosix: Self = .target(name: "GRPCHTTP2TransportNIOPosix")
  static let grpcHTTP2TransportNIOTransportServices: Self = .target(name: "GRPCHTTP2TransportNIOTransportServices")
}

// MARK: - Targets

extension Target {
  static let grpc: Target = .target(
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
    path: "Sources/GRPC"
  )

  static let grpcCore: Target = .target(
    name: "GRPCCore",
    dependencies: [
      .dequeModule,
      .atomics
    ],
    path: "Sources/GRPCCore"
  )

  static let grpcInProcessTransport: Target = .target(
    name: "GRPCInProcessTransport",
    dependencies: [
      .grpcCore
    ]
  )

  static let grpcInterceptors: Target = .target(
    name: "GRPCInterceptors",
    dependencies: [
      .grpcCore,
      .tracing
    ]
  )

  static let grpcHTTP2Core: Target = .target(
    name: "GRPCHTTP2Core",
    dependencies: [
      .grpcCore,
      .nioCore,
      .nioHTTP2,
      .cgrpcZlib,
      .dequeModule
    ]
  )

  static let grpcHTTP2TransportNIOPosix: Target = .target(
    name: "GRPCHTTP2TransportNIOPosix",
    dependencies: [
      .grpcHTTP2Core
    ]
  )

  static let grpcHTTP2TransportNIOTransportServices: Target = .target(
    name: "GRPCHTTP2TransportNIOTransportServices",
    dependencies: [
      .grpcHTTP2Core
    ]
  )

  static let cgrpcZlib: Target = .target(
    name: cgrpcZlibTargetName,
    path: "Sources/CGRPCZlib",
    linkerSettings: [
      .linkedLibrary("z"),
    ]
  )

  static let protocGenGRPCSwift: Target = .executableTarget(
    name: "protoc-gen-grpc-swift",
    dependencies: [
      .protobuf,
      .protobufPluginLibrary,
      .grpcCodeGen,
      .grpcProtobufCodeGen
    ],
    exclude: [
      "README.md",
    ]
  )

  static let grpcSwiftPlugin: Target = .plugin(
    name: "GRPCSwiftPlugin",
    capability: .buildTool(),
    dependencies: [
      .protocGenGRPCSwift,
    ]
  )

  static let grpcTests: Target = .testTarget(
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
    ]
  )

  static let grpcCoreTests: Target = .testTarget(
    name: "GRPCCoreTests",
    dependencies: [
      .grpcCore,
      .grpcInProcessTransport,
      .dequeModule,
      .atomics
    ]
  )

  static let grpcInProcessTransportTests: Target = .testTarget(
    name: "GRPCInProcessTransportTests",
    dependencies: [
      .grpcCore,
      .grpcInProcessTransport
    ]
  )

  static let grpcInterceptorsTests: Target = .testTarget(
    name: "GRPCInterceptorsTests",
    dependencies: [
      .grpcCore,
      .tracing,
      .nioCore,
      .grpcInterceptors
    ]
  )

  static let grpcHTTP2CoreTests: Target = .testTarget(
    name: "GRPCHTTP2CoreTests",
    dependencies: [
      .grpcHTTP2Core,
      .nioCore,
      .nioHTTP2,
      .nioEmbedded,
      .nioTestUtils,
    ]
  )

  static let grpcHTTP2TransportNIOPosixTests: Target = .testTarget(
    name: "GRPCHTTP2TransportNIOPosixTests",
    dependencies: [
      .grpcHTTP2TransportNIOPosix
    ]
  )

  static let grpcHTTP2TransportNIOTransportServicesTests: Target = .testTarget(
    name: "GRPCHTTP2TransportNIOTransportServicesTests",
    dependencies: [
      .grpcHTTP2TransportNIOTransportServices
    ]
  )

  static let grpcCodeGenTests: Target = .testTarget(
    name: "GRPCCodeGenTests",
    dependencies: [
      .grpcCodeGen
    ]
  )

  static let grpcProtobufTests: Target = .testTarget(
    name: "GRPCProtobufTests",
    dependencies: [
      .grpcProtobuf,
      .grpcCore,
      .protobuf
    ]
  )

  static let grpcProtobufCodeGenTests: Target = .testTarget(
    name: "GRPCProtobufCodeGenTests",
    dependencies: [
      .grpcCodeGen,
      .grpcProtobufCodeGen,
      .protobuf,
      .protobufPluginLibrary
    ]
  )

  static let interopTestModels: Target = .target(
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
    ]
  )

  static let interopTestImplementation: Target = .target(
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
    )
  )

  static let interopTests: Target = .executableTarget(
    name: "GRPCInteroperabilityTests",
    dependencies: [
      .grpc,
      .interopTestImplementation,
      .nioCore,
      .nioPosix,
      .logging,
      .argumentParser,
    ]
  )

  static let backoffInteropTest: Target = .executableTarget(
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
    ]
  )

  static let perfTests: Target = .executableTarget(
    name: "GRPCPerformanceTests",
    dependencies: [
      .grpc,
      .grpcSampleData,
      .nioCore,
      .nioEmbedded,
      .nioPosix,
      .nioHTTP2,
      .argumentParser,
    ]
  )

  static let grpcSampleData: Target = .target(
    name: "GRPCSampleData",
    dependencies: includeNIOSSL ? [.nioSSL] : [],
    exclude: [
      "bundle.p12",
    ]
  )

  static let echoModel: Target = .target(
    name: "EchoModel",
    dependencies: [
      .grpc,
      .nio,
      .protobuf,
    ],
    path: "Sources/Examples/Echo/Model"
  )

  static let echoImplementation: Target = .target(
    name: "EchoImplementation",
    dependencies: [
      .echoModel,
      .grpc,
      .nioCore,
      .nioHTTP2,
      .protobuf,
    ],
    path: "Sources/Examples/Echo/Implementation"
  )

  static let echo: Target = .executableTarget(
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
    path: "Sources/Examples/Echo/Runtime"
  )

  static let helloWorldModel: Target = .target(
    name: "HelloWorldModel",
    dependencies: [
      .grpc,
      .nio,
      .protobuf,
    ],
    path: "Sources/Examples/HelloWorld/Model"
  )

  static let helloWorldClient: Target = .executableTarget(
    name: "HelloWorldClient",
    dependencies: [
      .grpc,
      .helloWorldModel,
      .nioCore,
      .nioPosix,
      .argumentParser,
    ],
    path: "Sources/Examples/HelloWorld/Client"
  )

  static let helloWorldServer: Target = .executableTarget(
    name: "HelloWorldServer",
    dependencies: [
      .grpc,
      .helloWorldModel,
      .nioCore,
      .nioPosix,
      .argumentParser,
    ],
    path: "Sources/Examples/HelloWorld/Server"
  )

  static let routeGuideModel: Target = .target(
    name: "RouteGuideModel",
    dependencies: [
      .grpc,
      .nio,
      .protobuf,
    ],
    path: "Sources/Examples/RouteGuide/Model"
  )

  static let routeGuideClient: Target = .executableTarget(
    name: "RouteGuideClient",
    dependencies: [
      .grpc,
      .routeGuideModel,
      .nioCore,
      .nioPosix,
      .argumentParser,
    ],
    path: "Sources/Examples/RouteGuide/Client"
  )

  static let routeGuideServer: Target = .executableTarget(
    name: "RouteGuideServer",
    dependencies: [
      .grpc,
      .routeGuideModel,
      .nioCore,
      .nioConcurrencyHelpers,
      .nioPosix,
      .argumentParser,
    ],
    path: "Sources/Examples/RouteGuide/Server"
  )

  static let packetCapture: Target = .executableTarget(
    name: "PacketCapture",
    dependencies: [
      .grpc,
      .echoModel,
      .nioCore,
      .nioPosix,
      .nioExtras,
      .argumentParser,
    ],
    path: "Sources/Examples/PacketCapture",
    exclude: [
      "README.md",
    ]
  )

  static let reflectionService: Target = .target(
    name: "GRPCReflectionService",
    dependencies: [
      .grpc,
      .nio,
      .protobuf,
    ],
    path: "Sources/GRPCReflectionService"
  )

  static let reflectionServer: Target = .executableTarget(
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
    path: "Sources/Examples/ReflectionService",
    resources: [
      .copy("Generated")
    ]
  )

  static let grpcCodeGen: Target = .target(
    name: "GRPCCodeGen",
    path: "Sources/GRPCCodeGen"
  )

  static let grpcProtobuf: Target = .target(
    name: "GRPCProtobuf",
    dependencies: [
      .grpcCore,
      .protobuf,
    ],
    path: "Sources/GRPCProtobuf"
  )
  static let grpcProtobufCodeGen: Target = .target(
    name: "GRPCProtobufCodeGen",
    dependencies: [
      .protobuf,
      .protobufPluginLibrary,
      .grpcCodeGen
    ],
    path: "Sources/GRPCProtobufCodeGen"
  )
}

// MARK: - Products

extension Product {
  static let grpc: Product = .library(
    name: grpcProductName,
    targets: [grpcTargetName]
  )

  static let grpcCore: Product = .library(
    name: "_GRPCCore",
    targets: ["GRPCCore"]
  )

  static let cgrpcZlib: Product = .library(
    name: cgrpcZlibProductName,
    targets: [cgrpcZlibTargetName]
  )

  static let grpcReflectionService: Product = .library(
    name: "GRPCReflectionService",
    targets: ["GRPCReflectionService"]
  )

  static let protocGenGRPCSwift: Product = .executable(
    name: "protoc-gen-grpc-swift",
    targets: ["protoc-gen-grpc-swift"]
  )

  static let grpcSwiftPlugin: Product = .plugin(
    name: "GRPCSwiftPlugin",
    targets: ["GRPCSwiftPlugin"]
  )
}

// MARK: - Package

let package = Package(
  name: grpcPackageName,
  products: [
    .grpc,
    .grpcCore,
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

    // v2 tests
    .grpcCoreTests,
    .grpcInProcessTransportTests,
    .grpcCodeGenTests,
    .grpcInterceptorsTests,
    .grpcHTTP2CoreTests,
    .grpcHTTP2TransportNIOPosixTests,
    .grpcHTTP2TransportNIOTransportServicesTests,
    .grpcProtobufTests,
    .grpcProtobufCodeGenTests
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
