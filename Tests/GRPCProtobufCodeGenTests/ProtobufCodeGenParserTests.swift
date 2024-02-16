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

import GRPCCodeGen
import SwiftProtobuf
import SwiftProtobufPluginLibrary
import XCTest

@testable import GRPCProtobufCodeGen

final class ProtobufCodeGenParserTests: XCTestCase {
  func testParser() throws {
    let descriptorSet = DescriptorSet(
      protos: [
        Google_Protobuf_FileDescriptorProto(
          name: "same-module.proto",
          package: "same-package"
        ),
        Google_Protobuf_FileDescriptorProto(
          name: "different-module.proto",
          package: "different-package"
        ),
        Google_Protobuf_FileDescriptorProto.helloWorld,
      ]
    )

    guard let fileDescriptor = descriptorSet.fileDescriptor(named: "helloworld.proto") else {
      return XCTFail(
        """
        Could not find the file descriptor of "helloworld.proto".
        """
      )
    }
    let moduleMappings = SwiftProtobuf_GenSwift_ModuleMappings.with {
      $0.mapping = [
        SwiftProtobuf_GenSwift_ModuleMappings.Entry.with {
          $0.protoFilePath = ["different-module.proto"]
          $0.moduleName = "DifferentModule"
        }
      ]
    }
    let parsedCodeGenRequest = try ProtobufCodeGenParser(
      input: fileDescriptor,
      protoFileModuleMappings: ProtoFileToModuleMappings(moduleMappingsProto: moduleMappings),
      extraModuleImports: ["ExtraModule"]
    ).parse()

    self.testCommonHelloworldParsedRequestFields(for: parsedCodeGenRequest)

    let expectedMethod = CodeGenerationRequest.ServiceDescriptor.MethodDescriptor(
      documentation: "/// Sends a greeting.\n",
      name: CodeGenerationRequest.Name(
        base: "SayHello",
        generatedUpperCase: "SayHello",
        generatedLowerCase: "sayHello"
      ),
      isInputStreaming: false,
      isOutputStreaming: false,
      inputType: "Helloworld_HelloRequest",
      outputType: "Helloworld_HelloReply"
    )
    guard let method = parsedCodeGenRequest.services.first?.methods.first else { return XCTFail() }
    XCTAssertEqual(method, expectedMethod)

    let expectedService = CodeGenerationRequest.ServiceDescriptor(
      documentation: "/// The greeting service definition.\n",
      name: CodeGenerationRequest.Name(
        base: "Greeter",
        generatedUpperCase: "Greeter",
        generatedLowerCase: "greeter"
      ),
      namespace: CodeGenerationRequest.Name(
        base: "helloworld",
        generatedUpperCase: "Helloworld",
        generatedLowerCase: "helloworld"
      ),
      methods: [expectedMethod]
    )
    guard let service = parsedCodeGenRequest.services.first else { return XCTFail() }
    XCTAssertEqual(service, expectedService)
    XCTAssertEqual(service.methods.count, 1)

    XCTAssertEqual(
      parsedCodeGenRequest.lookupSerializer("Helloworld_HelloRequest"),
      "ProtobufSerializer<Helloworld_HelloRequest>()"
    )
    XCTAssertEqual(
      parsedCodeGenRequest.lookupDeserializer("Helloworld_HelloRequest"),
      "ProtobufDeserializer<Helloworld_HelloRequest>()"
    )
  }

  func testParserNestedPackage() throws {
    let descriptorSet = DescriptorSet(
      protos: [
        Google_Protobuf_FileDescriptorProto(
          name: "same-module.proto",
          package: "same-package"
        ),
        Google_Protobuf_FileDescriptorProto(
          name: "different-module.proto",
          package: "different-package"
        ),
        Google_Protobuf_FileDescriptorProto.helloWorldNestedPackage,
      ]
    )

    guard let fileDescriptor = descriptorSet.fileDescriptor(named: "helloworld.proto") else {
      return XCTFail(
        """
        Could not find the file descriptor of "helloworld.proto".
        """
      )
    }
    let moduleMappings = SwiftProtobuf_GenSwift_ModuleMappings.with {
      $0.mapping = [
        SwiftProtobuf_GenSwift_ModuleMappings.Entry.with {
          $0.protoFilePath = ["different-module.proto"]
          $0.moduleName = "DifferentModule"
        }
      ]
    }
    let parsedCodeGenRequest = try ProtobufCodeGenParser(
      input: fileDescriptor,
      protoFileModuleMappings: ProtoFileToModuleMappings(moduleMappingsProto: moduleMappings),
      extraModuleImports: ["ExtraModule"]
    ).parse()

    self.testCommonHelloworldParsedRequestFields(for: parsedCodeGenRequest)

    let expectedMethod = CodeGenerationRequest.ServiceDescriptor.MethodDescriptor(
      documentation: "/// Sends a greeting.\n",
      name: CodeGenerationRequest.Name(
        base: "SayHello",
        generatedUpperCase: "SayHello",
        generatedLowerCase: "sayHello"
      ),
      isInputStreaming: false,
      isOutputStreaming: false,
      inputType: "Hello_World_HelloRequest",
      outputType: "Hello_World_HelloReply"
    )
    guard let method = parsedCodeGenRequest.services.first?.methods.first else { return XCTFail() }
    XCTAssertEqual(method, expectedMethod)

    let expectedService = CodeGenerationRequest.ServiceDescriptor(
      documentation: "/// The greeting service definition.\n",
      name: CodeGenerationRequest.Name(
        base: "Greeter",
        generatedUpperCase: "Greeter",
        generatedLowerCase: "greeter"
      ),
      namespace: CodeGenerationRequest.Name(
        base: "hello.world",
        generatedUpperCase: "Hello_World",
        generatedLowerCase: "hello_world"
      ),
      methods: [expectedMethod]
    )
    guard let service = parsedCodeGenRequest.services.first else { return XCTFail() }
    XCTAssertEqual(service, expectedService)
    XCTAssertEqual(service.methods.count, 1)

    XCTAssertEqual(
      parsedCodeGenRequest.lookupSerializer("Hello_World_HelloRequest"),
      "ProtobufSerializer<Hello_World_HelloRequest>()"
    )
    XCTAssertEqual(
      parsedCodeGenRequest.lookupDeserializer("Hello_World_HelloRequest"),
      "ProtobufDeserializer<Hello_World_HelloRequest>()"
    )
  }

  func testParserEmptyPackage() throws {
    let descriptorSet = DescriptorSet(
      protos: [
        Google_Protobuf_FileDescriptorProto(
          name: "same-module.proto",
          package: "same-package"
        ),
        Google_Protobuf_FileDescriptorProto(
          name: "different-module.proto",
          package: "different-package"
        ),
        Google_Protobuf_FileDescriptorProto.helloWorldEmptyPackage,
      ]
    )

    guard let fileDescriptor = descriptorSet.fileDescriptor(named: "helloworld.proto") else {
      return XCTFail(
        """
        Could not find the file descriptor of "helloworld.proto".
        """
      )
    }
    let moduleMappings = SwiftProtobuf_GenSwift_ModuleMappings.with {
      $0.mapping = [
        SwiftProtobuf_GenSwift_ModuleMappings.Entry.with {
          $0.protoFilePath = ["different-module.proto"]
          $0.moduleName = "DifferentModule"
        }
      ]
    }
    let parsedCodeGenRequest = try ProtobufCodeGenParser(
      input: fileDescriptor,
      protoFileModuleMappings: ProtoFileToModuleMappings(moduleMappingsProto: moduleMappings),
      extraModuleImports: ["ExtraModule"]
    ).parse()

    self.testCommonHelloworldParsedRequestFields(for: parsedCodeGenRequest)

    let expectedMethod = CodeGenerationRequest.ServiceDescriptor.MethodDescriptor(
      documentation: "/// Sends a greeting.\n",
      name: CodeGenerationRequest.Name(
        base: "SayHello",
        generatedUpperCase: "SayHello",
        generatedLowerCase: "sayHello"
      ),
      isInputStreaming: false,
      isOutputStreaming: false,
      inputType: "HelloRequest",
      outputType: "HelloReply"
    )
    guard let method = parsedCodeGenRequest.services.first?.methods.first else { return XCTFail() }
    XCTAssertEqual(method, expectedMethod)

    let expectedService = CodeGenerationRequest.ServiceDescriptor(
      documentation: "/// The greeting service definition.\n",
      name: CodeGenerationRequest.Name(
        base: "Greeter",
        generatedUpperCase: "Greeter",
        generatedLowerCase: "greeter"
      ),
      namespace: CodeGenerationRequest.Name(
        base: "",
        generatedUpperCase: "",
        generatedLowerCase: ""
      ),
      methods: [expectedMethod]
    )
    guard let service = parsedCodeGenRequest.services.first else { return XCTFail() }
    XCTAssertEqual(service, expectedService)
    XCTAssertEqual(service.methods.count, 1)

    XCTAssertEqual(
      parsedCodeGenRequest.lookupSerializer("HelloRequest"),
      "ProtobufSerializer<HelloRequest>()"
    )
    XCTAssertEqual(
      parsedCodeGenRequest.lookupDeserializer("HelloRequest"),
      "ProtobufDeserializer<HelloRequest>()"
    )
  }
}

extension ProtobufCodeGenParserTests {
  func testCommonHelloworldParsedRequestFields(for request: CodeGenerationRequest) {
    XCTAssertEqual(request.fileName, "helloworld.proto")
    XCTAssertEqual(
      request.leadingTrivia,
      """
      // Copyright 2015 gRPC authors.
      //
      // Licensed under the Apache License, Version 2.0 (the "License");
      // you may not use this file except in compliance with the License.
      // You may obtain a copy of the License at
      //
      //     http://www.apache.org/licenses/LICENSE-2.0
      //
      // Unless required by applicable law or agreed to in writing, software
      // distributed under the License is distributed on an "AS IS" BASIS,
      // WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
      // See the License for the specific language governing permissions and
      // limitations under the License.

      // DO NOT EDIT.
      // swift-format-ignore-file
      //
      // Generated by the gRPC Swift generator plugin for the protocol buffer compiler.
      // Source: helloworld.proto
      //
      // For information on using the generated types, please see the documentation:
      //   https://github.com/grpc/grpc-swift

      """
    )
    XCTAssertEqual(request.dependencies.count, 3)
    let expectedDependencyNames = ["GRPCProtobuf", "DifferentModule", "ExtraModule"]
    let parsedDependencyNames = request.dependencies.map { $0.module }
    XCTAssertEqual(parsedDependencyNames, expectedDependencyNames)
    XCTAssertEqual(request.services.count, 1)
  }
}

extension Google_Protobuf_FileDescriptorProto {
  static var helloWorld: Google_Protobuf_FileDescriptorProto {
    let requestType = Google_Protobuf_DescriptorProto.with {
      $0.name = "HelloRequest"
      $0.field = [
        Google_Protobuf_FieldDescriptorProto.with {
          $0.name = "name"
          $0.number = 1
          $0.label = .optional
          $0.type = .string
          $0.jsonName = "name"
        }
      ]
    }
    let responseType = Google_Protobuf_DescriptorProto.with {
      $0.name = "HelloReply"
      $0.field = [
        Google_Protobuf_FieldDescriptorProto.with {
          $0.name = "message"
          $0.number = 1
          $0.label = .optional
          $0.type = .string
          $0.jsonName = "message"
        }
      ]
    }

    let service = Google_Protobuf_ServiceDescriptorProto.with {
      $0.name = "Greeter"
      $0.method = [
        Google_Protobuf_MethodDescriptorProto.with {
          $0.name = "SayHello"
          $0.inputType = ".helloworld.HelloRequest"
          $0.outputType = ".helloworld.HelloReply"
          $0.clientStreaming = false
          $0.serverStreaming = false
        }
      ]
    }
    return Google_Protobuf_FileDescriptorProto.with {
      $0.name = "helloworld.proto"
      $0.package = "helloworld"
      $0.dependency = ["same-module.proto", "different-module.proto"]
      $0.publicDependency = [1, 2]
      $0.messageType = [requestType, responseType]
      $0.service = [service]
      $0.sourceCodeInfo = Google_Protobuf_SourceCodeInfo.with {
        $0.location = [
          Google_Protobuf_SourceCodeInfo.Location.with {
            $0.path = [12]
            $0.span = [14, 0, 18]
            $0.leadingDetachedComments = [
              """
               Copyright 2015 gRPC authors.

               Licensed under the Apache License, Version 2.0 (the \"License\");
               you may not use this file except in compliance with the License.
               You may obtain a copy of the License at

                   http://www.apache.org/licenses/LICENSE-2.0

               Unless required by applicable law or agreed to in writing, software
               distributed under the License is distributed on an \"AS IS\" BASIS,
               WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
               See the License for the specific language governing permissions and
               limitations under the License.

              """
            ]
          },
          Google_Protobuf_SourceCodeInfo.Location.with {
            $0.path = [6, 0]
            $0.span = [19, 0, 22, 1]
            $0.leadingComments = " The greeting service definition.\n"
          },
          Google_Protobuf_SourceCodeInfo.Location.with {
            $0.path = [6, 0, 2, 0]
            $0.span = [21, 2, 53]
            $0.leadingComments = " Sends a greeting.\n"
          },
        ]
      }
      $0.syntax = "proto3"
    }
  }

  static var helloWorldNestedPackage: Google_Protobuf_FileDescriptorProto {
    let service = Google_Protobuf_ServiceDescriptorProto.with {
      $0.name = "Greeter"
      $0.method = [
        Google_Protobuf_MethodDescriptorProto.with {
          $0.name = "SayHello"
          $0.inputType = ".hello.world.HelloRequest"
          $0.outputType = ".hello.world.HelloReply"
          $0.clientStreaming = false
          $0.serverStreaming = false
        }
      ]
    }

    var helloWorldCopy = self.helloWorld
    helloWorldCopy.package = "hello.world"
    helloWorldCopy.service = [service]

    return helloWorldCopy
  }

  static var helloWorldEmptyPackage: Google_Protobuf_FileDescriptorProto {
    let service = Google_Protobuf_ServiceDescriptorProto.with {
      $0.name = "Greeter"
      $0.method = [
        Google_Protobuf_MethodDescriptorProto.with {
          $0.name = "SayHello"
          $0.inputType = ".HelloRequest"
          $0.outputType = ".HelloReply"
          $0.clientStreaming = false
          $0.serverStreaming = false
        }
      ]
    }
    var helloWorldCopy = self.helloWorld
    helloWorldCopy.package = ""
    helloWorldCopy.service = [service]

    return helloWorldCopy
  }

  internal init(name: String, package: String) {
    self.init()
    self.name = name
    self.package = package
  }
}
