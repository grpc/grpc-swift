/*
 * Copyright 2022, gRPC Authors All rights reserved.
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

import Foundation
import PackagePlugin

@main
struct GRPCSwiftPlugin {
  /// Errors thrown by the `GRPCSwiftPlugin`
  enum PluginError: Error, CustomStringConvertible {
    /// Indicates that the target where the plugin was applied to was not `SourceModuleTarget`.
    case invalidTarget(String)
    /// Indicates that the file extension of an input file was not `.proto`.
    case invalidInputFileExtension(String)
    /// Indicates that there was no configuration file at the required location.
    case noConfigFound(String)

    var description: String {
      switch self {
      case let .invalidTarget(target):
        return "Expected a SwiftSourceModuleTarget but got '\(target)'."
      case let .invalidInputFileExtension(path):
        return "The input file '\(path)' does not have a '.proto' extension."
      case let .noConfigFound(path):
        return """
          No configuration file found named '\(path)'. The file must not be listed in the \
          'exclude:' argument for the target in Package.swift.
          """
      }
    }
  }

  /// The configuration of the plugin.
  struct Configuration: Codable {
    /// Encapsulates a single invocation of protoc.
    struct Invocation: Codable {
      /// The visibility of the generated files.
      enum Visibility: String, Codable {
        /// The generated files should have `internal` access level.
        case `internal`
        /// The generated files should have `public` access level.
        case `public`
        /// The generated files should have `package` access level.
        case `package`
      }

      /// An array of paths to `.proto` files for this invocation.
      var protoFiles: [String]
      /// The visibility of the generated files.
      var visibility: Visibility?
      /// Whether server code is generated.
      var server: Bool?
      /// Whether client code is generated.
      var client: Bool?
      /// Whether reflection data is generated.
      var reflectionData: Bool?
      /// Determines whether the casing of generated function names is kept.
      var keepMethodCasing: Bool?
      /// Whether the invocation is for `grpc-swift` v2.
      var _V2: Bool?
    }

    /// Specify the directory in which to search for
    /// imports.  May be specified multiple times;
    /// directories will be searched in order.
    /// The target source directory is always appended
    /// to the import paths.
    var importPaths: [String]?

    /// The path to the `protoc` binary.
    ///
    /// If this is not set, SPM will try to find the tool itself.
    var protocPath: String?

    /// A list of invocations of `protoc` with the `GRPCSwiftPlugin`.
    var invocations: [Invocation]
  }

  static let configurationFileName = "grpc-swift-config.json"

  /// Create build commands for the given arguments
  /// - Parameters:
  ///   - pluginWorkDirectory: The path of a writable directory into which the plugin or the build
  ///   commands it constructs can write anything it wants.
  ///   - sourceFiles: The input files that are associated with the target.
  ///   - tool: The tool method from the context.
  /// - Returns: The build commands configured based on the arguments.
  func createBuildCommands(
    pluginWorkDirectory: PathLike,
    sourceFiles: FileList,
    tool: (String) throws -> PackagePlugin.PluginContext.Tool
  ) throws -> [Command] {
    let maybeConfigFile = sourceFiles.map { PathLike($0) }.first {
      $0.lastComponent == Self.configurationFileName
    }

    guard let configurationFilePath = maybeConfigFile else {
      throw PluginError.noConfigFound(Self.configurationFileName)
    }

    let data = try Data(contentsOf: URL(configurationFilePath))
    let configuration = try JSONDecoder().decode(Configuration.self, from: data)

    try self.validateConfiguration(configuration)

    let targetDirectory = configurationFilePath.removingLastComponent()
    var importPaths: [PathLike] = [targetDirectory]
    if let configuredImportPaths = configuration.importPaths {
      importPaths.append(contentsOf: configuredImportPaths.map { PathLike($0) })
    }

    // We need to find the path of protoc and protoc-gen-grpc-swift
    let protocPath: PathLike
    if let configuredProtocPath = configuration.protocPath {
      protocPath = PathLike(configuredProtocPath)
    } else if let environmentPath = ProcessInfo.processInfo.environment["PROTOC_PATH"] {
      // The user set the env variable, so let's take that
      protocPath = PathLike(environmentPath)
    } else {
      // The user didn't set anything so let's try see if SPM can find a binary for us
      protocPath = try PathLike(tool("protoc"))
    }

    let protocGenGRPCSwiftPath = try PathLike(tool("protoc-gen-grpc-swift"))

    return configuration.invocations.map { invocation in
      self.invokeProtoc(
        directory: targetDirectory,
        invocation: invocation,
        protocPath: protocPath,
        protocGenGRPCSwiftPath: protocGenGRPCSwiftPath,
        outputDirectory: pluginWorkDirectory,
        importPaths: importPaths
      )
    }
  }

  /// Invokes `protoc` with the given inputs
  ///
  /// - Parameters:
  ///   - directory: The plugin's target directory.
  ///   - invocation: The `protoc` invocation.
  ///   - protocPath: The path to the `protoc` binary.
  ///   - protocGenSwiftPath: The path to the `protoc-gen-swift` binary.
  ///   - outputDirectory: The output directory for the generated files.
  ///   - importPaths: List of paths to pass with "-I <path>" to `protoc`.
  /// - Returns: The build command configured based on the arguments
  private func invokeProtoc(
    directory: PathLike,
    invocation: Configuration.Invocation,
    protocPath: PathLike,
    protocGenGRPCSwiftPath: PathLike,
    outputDirectory: PathLike,
    importPaths: [PathLike]
  ) -> Command {
    // Construct the `protoc` arguments.
    var protocArgs = [
      "--plugin=protoc-gen-grpc-swift=\(protocGenGRPCSwiftPath)",
      "--grpc-swift_out=\(outputDirectory)",
    ]

    importPaths.forEach { path in
      protocArgs.append("-I")
      protocArgs.append("\(path)")
    }

    if let visibility = invocation.visibility {
      protocArgs.append("--grpc-swift_opt=Visibility=\(visibility.rawValue.capitalized)")
    }

    if let generateServerCode = invocation.server {
      protocArgs.append("--grpc-swift_opt=Server=\(generateServerCode)")
    }

    if let generateClientCode = invocation.client {
      protocArgs.append("--grpc-swift_opt=Client=\(generateClientCode)")
    }

    if let generateReflectionData = invocation.reflectionData {
      protocArgs.append("--grpc-swift_opt=ReflectionData=\(generateReflectionData)")
    }

    if let keepMethodCasingOption = invocation.keepMethodCasing {
      protocArgs.append("--grpc-swift_opt=KeepMethodCasing=\(keepMethodCasingOption)")
    }

    if let v2 = invocation._V2 {
      protocArgs.append("--grpc-swift_opt=_V2=\(v2)")
    }

    var inputFiles = [PathLike]()
    var outputFiles = [PathLike]()

    for var file in invocation.protoFiles {
      // Append the file to the protoc args so that it is used for generating
      protocArgs.append(file)
      inputFiles.append(directory.appending(file))

      // The name of the output file is based on the name of the input file.
      // We validated in the beginning that every file has the suffix of .proto
      // This means we can just drop the last 5 elements and append the new suffix
      file.removeLast(5)
      file.append("grpc.swift")
      let protobufOutputPath = outputDirectory.appending(file)

      // Add the outputPath as an output file
      outputFiles.append(protobufOutputPath)

      if invocation.reflectionData == true {
        // Remove .swift extension and add .reflection extension
        file.removeLast(5)
        file.append("reflection")
        let reflectionOutputPath = outputDirectory.appending(file)
        outputFiles.append(reflectionOutputPath)
      }
    }

    // Construct the command. Specifying the input and output paths lets the build
    // system know when to invoke the command. The output paths are passed on to
    // the rule engine in the build system.
    return Command.buildCommand(
      displayName: "Generating gRPC Swift files from proto files",
      executable: protocPath,
      arguments: protocArgs,
      inputFiles: inputFiles + [protocGenGRPCSwiftPath],
      outputFiles: outputFiles
    )
  }

  /// Validates the configuration file for various user errors.
  private func validateConfiguration(_ configuration: Configuration) throws {
    for invocation in configuration.invocations {
      for protoFile in invocation.protoFiles {
        if !protoFile.hasSuffix(".proto") {
          throw PluginError.invalidInputFileExtension(protoFile)
        }
      }
    }
  }
}

extension GRPCSwiftPlugin: BuildToolPlugin {
  func createBuildCommands(
    context: PluginContext,
    target: Target
  ) async throws -> [Command] {
    guard let swiftTarget = target as? SwiftSourceModuleTarget else {
      throw PluginError.invalidTarget("\(type(of: target))")
    }

    let workDirectory = PathLike(context.pluginWorkDirectory)

    return try self.createBuildCommands(
      pluginWorkDirectory: workDirectory,
      sourceFiles: swiftTarget.sourceFiles,
      tool: context.tool
    )
  }
}

// 'Path' was effectively deprecated in Swift 6 in favour of URL. ('Effectively' because all
// methods, properties, and conformances have been deprecated but the type hasn't.) This type wraps
// either depending on the compiler version.
struct PathLike: CustomStringConvertible {
  typealias Value = Path

  private(set) var value: Value

  init(_ value: Value) {
    self.value = value
  }

  init(_ path: String) {
    self.value = Path(path)
  }

  init(_ element: FileList.Element) {
    self.value = element.path
  }

  init(_ element: PluginContext.Tool) {
    self.value = element.path
  }

  var description: String {
    return String(describing: self.value)
  }

  var lastComponent: String {
    return self.value.lastComponent
  }

  func removingLastComponent() -> Self {
    var copy = self
    copy.value = self.value.removingLastComponent()
    return copy
  }

  func appending(_ path: String) -> Self {
    var copy = self
    copy.value = self.value.appending(path)
    return copy
  }
}

extension Command {
  static func buildCommand(
    displayName: String?,
    executable: PathLike,
    arguments: [String],
    inputFiles: [PathLike],
    outputFiles: [PathLike]
  ) -> PackagePlugin.Command {
    return Self.buildCommand(
      displayName: displayName,
      executable: executable.value,
      arguments: arguments,
      inputFiles: inputFiles.map { $0.value },
      outputFiles: outputFiles.map { $0.value }
    )
  }
}

extension URL {
  init(_ pathLike: PathLike) {
    self = URL(fileURLWithPath: "\(pathLike.value)")
  }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension GRPCSwiftPlugin: XcodeBuildToolPlugin {
  func createBuildCommands(
    context: XcodePluginContext,
    target: XcodeTarget
  ) throws -> [Command] {
    let workDirectory = PathLike(context.pluginWorkDirectory)

    return try self.createBuildCommands(
      pluginWorkDirectory: workDirectory,
      sourceFiles: target.inputFiles,
      tool: context.tool
    )
  }
}
#endif
