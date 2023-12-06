/*
 * Copyright 2023, gRPC Authors All rights reserved.
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

import XCTest

@testable import GRPCCodeGen

final class SnippetBasedTranslatorTests: XCTestCase {
  typealias MethodDescriptor = GRPCCodeGen.CodeGenerationRequest.ServiceDescriptor.MethodDescriptor
  typealias ServiceDescriptor = GRPCCodeGen.CodeGenerationRequest.ServiceDescriptor

  let echoMethods: [MethodDescriptor] = {
    var methods: [MethodDescriptor] = []
    methods.append(
      MethodDescriptor(
        documentation: "Immediately returns an echo of a request.",
        name: "Get",
        isInputStreaming: false,
        isOutputStreaming: false,
        inputType: "Echo_EchoRequest",
        outputType: "Echo_EchoResponse"
      )
    )
    methods.append(
      MethodDescriptor(
        documentation: "Splits a request into words and returns each word in a stream of messages.",
        name: "Expand",
        isInputStreaming: false,
        isOutputStreaming: true,
        inputType: "Echo_EchoRequest",
        outputType: "Echo_EchoResponse"
      )
    )
    methods.append(
      MethodDescriptor(
        documentation:
          "Collects a stream of messages and returns them concatenated when the caller closes.",
        name: "Collect",
        isInputStreaming: true,
        isOutputStreaming: false,
        inputType: "Echo_EchoRequest",
        outputType: "Echo_EchoResponse"
      )
    )
    methods.append(
      MethodDescriptor(
        documentation: "Streams back messages as they are received in an input stream.",
        name: "Update",
        isInputStreaming: true,
        isOutputStreaming: true,
        inputType: "Echo_EchoRequest",
        outputType: "Echo_EchoResponse"
      )
    )
    return methods
  }()

  var echoService: CodeGenerationRequest.ServiceDescriptor {
    CodeGenerationRequest.ServiceDescriptor(
      documentation: "An echo service.",
      name: "Echo",
      namespace: "echo",
      methods: echoMethods
    )
  }

  var codeGenerationRequest: CodeGenerationRequest {
    CodeGenerationRequest(
      fileName: "echo.grpc",
      leadingTrivia: "Some really exciting license header 2023.",
      dependencies: [],
      services: [self.echoService],
      lookupSerializer: {
        "ProtobufSerializer<\($0)>()"
      },
      lookupDeserializer: {
        "ProtobufDeserializer<\($0)>()"
      }
    )
  }

  func testTypealiasTranslate() throws {
    let expectedSwift =
      """
      enum echo {
          enum Echo {
              enum Collect {
                  typealias Input = Echo_EchoRequest
                  typealias Output = Echo_EchoResponse
                  static let descriptor = MethodDescriptor(
                      service: echo.Echo,
                      method: Collect
                  )
              }
              enum Expand {
                  typealias Input = Echo_EchoRequest
                  typealias Output = Echo_EchoResponse
                  static let descriptor = MethodDescriptor(
                      service: echo.Echo,
                      method: Expand
                  )
              }
              enum Get {
                  typealias Input = Echo_EchoRequest
                  typealias Output = Echo_EchoResponse
                  static let descriptor = MethodDescriptor(
                      service: echo.Echo,
                      method: Get
                  )
              }
              enum Update {
                  typealias Input = Echo_EchoRequest
                  typealias Output = Echo_EchoResponse
                  static let descriptor = MethodDescriptor(
                      service: echo.Echo,
                      method: Update
                  )
              }
              static let methods: [MethodDescriptor] = [
                  echo.Echo.Collect.descriptor,
                  echo.Echo.Expand.descriptor,
                  echo.Echo.Get.descriptor,
                  echo.Echo.Update.descriptor
              ]
              typealias StreamingServiceProtocol = echo_EchoServiceStreamingProtocol
              typealias ServiceProtocol = echo_EchoServiceProtocol
          }
      }
      """
    try self._assertTypealiasTranslation(
      codeGenerationRequest: self.codeGenerationRequest,
      expectedSwift: expectedSwift
    )
  }
}

extension SnippetBasedTranslatorTests {
  private func diff(expected: String, actual: String) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [
      "bash", "-c",
      "diff -U5 --label=expected <(echo '\(expected)') --label=actual <(echo '\(actual)')",
    ]
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    process.waitUntilExit()
    let pipeData = try XCTUnwrap(
      pipe.fileHandleForReading.readToEnd(),
      """
      No output from command:
      \(process.executableURL!.path) \(process.arguments!.joined(separator: " "))
      """
    )
    return String(decoding: pipeData, as: UTF8.self)
  }

  private func XCTAssertEqualWithDiff(
    _ actual: String,
    _ expected: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    if actual == expected { return }
    XCTFail(
      """
      XCTAssertEqualWithDiff failed (click for diff)
      \(try diff(expected: expected, actual: actual))
      """,
      file: file,
      line: line
    )
  }

  func _assertTypealiasTranslation(
    codeGenerationRequest: CodeGenerationRequest,
    expectedSwift: String
  ) throws {
    let translator = TypealiasTranslator()
    let codeBlocks = translator.translate(from: codeGenerationRequest)
    let renderer = TextBasedRenderer.default
    renderer.renderCodeBlocks(codeBlocks)
    let contents = renderer.renderedContents()
    try XCTAssertEqualWithDiff(contents, expectedSwift)
  }
}
