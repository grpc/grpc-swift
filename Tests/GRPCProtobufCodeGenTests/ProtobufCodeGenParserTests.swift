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
    let parsedCodeGenRequest = try ProtobufCodeGenParser().parse(
      input: helloWorldFileDescriptor
    )
    XCTAssertEqual(parsedCodeGenRequest.fileName, "helloworld.proto")
    XCTAssertEqual(
      parsedCodeGenRequest.leadingTrivia,
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

    XCTAssertEqual(parsedCodeGenRequest.services.count, 1)

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
      parsedCodeGenRequest.lookupSerializer("HelloRequest"),
      "ProtobufSerializer<HelloRequest>()"
    )
    XCTAssertEqual(
      parsedCodeGenRequest.lookupDeserializer("HelloRequest"),
      "ProtobufDeserializer<HelloRequest>()"
    )
    XCTAssertEqual(parsedCodeGenRequest.dependencies.count, 1)
    XCTAssertEqual(
      parsedCodeGenRequest.dependencies[0],
      CodeGenerationRequest.Dependency(module: "GRPCProtobuf")
    )
  }
}

var helloWorldFileDescriptor: FileDescriptor {
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
  let protoDescriptor = Google_Protobuf_FileDescriptorProto.with {
    $0.name = "helloworld.proto"
    $0.package = "helloworld"
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
  let descriptorSet = DescriptorSet(protos: [protoDescriptor])
  return descriptorSet.fileDescriptor(named: "helloworld.proto")!
}
