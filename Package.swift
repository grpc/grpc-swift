// swift-tools-version:5.6
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
    from: "1.26.0"
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
  static let logging: Self = .product(name: "Logging", package: "swift-log")
  static let protobuf: Self = .product(name: "SwiftProtobuf", package: "swift-protobuf")
  static let protobufPluginLibrary: Self = .product(
    name: "SwiftProtobufPluginLibrary",
    package: "swift-protobuf"
  )
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
    ].appending(
      .nioSSL, if: includeNIOSSL
    ),
    path: "Sources/GRPC"
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
    ].appending(
      .nioSSL, if: includeNIOSSL
    ),
    exclude: [
      "Codegen/Normalization/normalization.proto",
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
    path: "Sources/Examples/Echo/Model",
    exclude: [
      "echo.proto",
    ]
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
    path: "Sources/Examples/HelloWorld/Model",
    exclude: [
      "helloworld.proto",
    ]
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
    path: "Sources/Examples/RouteGuide/Model",
    exclude: [
      "route_guide.proto",
    ]
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
}

// MARK: - Products

extension Product {
  static let grpc: Product = .library(
    name: grpcProductName,
    targets: [grpcTargetName]
  )

  static let cgrpcZlib: Product = .library(
    name: cgrpcZlibProductName,
    targets: [cgrpcZlibTargetName]
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
    .cgrpcZlib,
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
