/*
 * Copyright 2021, gRPC Authors All rights reserved.
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
import SwiftProtobuf
import SwiftProtobufPluginLibrary

// MARK: - Client protocol

extension Generator {
  internal func printAsyncServiceClientProtocol() {
    let comments = self.service.protoSourceComments()
    if !comments.isEmpty {
      // Source comments already have the leading '///'
      self.println(comments, newline: false)
    }

    self.printAvailabilityForAsyncAwait()
    self.println("\(self.access) protocol \(self.asyncClientProtocolName): GRPCClient {")
    self.withIndentation {
      self.println("var serviceName: String { get }")
      self.println("var interceptors: \(self.clientInterceptorProtocolName)? { get }")

      for method in service.methods {
        self.println()
        self.method = method

        let rpcType = streamingType(self.method)
        let callType = Types.call(for: rpcType)

        let arguments: [String]
        switch rpcType {
        case .unary, .serverStreaming:
          arguments = [
            "_ request: \(self.methodInputName)",
            "callOptions: \(Types.clientCallOptions)?",
          ]

        case .clientStreaming, .bidirectionalStreaming:
          arguments = [
            "callOptions: \(Types.clientCallOptions)?",
          ]
        }

        self.printFunction(
          name: "make\(self.method.name)Call",
          arguments: arguments,
          returnType: "\(callType)<\(self.methodInputName), \(self.methodOutputName)>",
          bodyBuilder: nil
        )
      }
    }
    self.println("}") // protocol
  }
}

// MARK: - Client protocol default implementation: Calls

extension Generator {
  internal func printAsyncClientProtocolExtension() {
    self.printAvailabilityForAsyncAwait()
    self.withIndentation("extension \(self.asyncClientProtocolName)", braces: .curly) {
      // Service name. TODO: use static metadata.
      self.withIndentation("\(self.access) var serviceName: String", braces: .curly) {
        self.println("return \"\(self.servicePath)\"")
      }
      self.println()

      // Interceptor factory.
      self.withIndentation(
        "\(self.access) var interceptors: \(self.clientInterceptorProtocolName)?",
        braces: .curly
      ) {
        self.println("return nil")
      }

      // 'Unsafe' calls.
      for method in self.service.methods {
        self.println()
        self.method = method

        let rpcType = streamingType(self.method)
        let callType = Types.call(for: rpcType)
        let callTypeWithoutPrefix = Types.call(for: rpcType, withGRPCPrefix: false)

        switch rpcType {
        case .unary, .serverStreaming:
          self.printFunction(
            name: "make\(self.method.name)Call",
            arguments: [
              "_ request: \(self.methodInputName)",
              "callOptions: \(Types.clientCallOptions)? = nil",
            ],
            returnType: "\(callType)<\(self.methodInputName), \(self.methodOutputName)>",
            access: self.access
          ) {
            self.withIndentation("return self.make\(callTypeWithoutPrefix)", braces: .round) {
              self.println("path: \(self.methodPath),")
              self.println("request: request,")
              self.println("callOptions: callOptions ?? self.defaultCallOptions")
            }
          }

        case .clientStreaming, .bidirectionalStreaming:
          self.printFunction(
            name: "make\(self.method.name)Call",
            arguments: ["callOptions: \(Types.clientCallOptions)? = nil"],
            returnType: "\(callType)<\(self.methodInputName), \(self.methodOutputName)>",
            access: self.access
          ) {
            self.withIndentation("return self.make\(callTypeWithoutPrefix)", braces: .round) {
              self.println("path: \(self.methodPath),")
              self.println("callOptions: callOptions ?? self.defaultCallOptions")
            }
          }
        }
      }
    }
  }
}

// MARK: - Client protocol extension: "Simple, but safe" call wrappers.

extension Generator {
  internal func printAsyncClientProtocolSafeWrappersExtension() {
    self.printAvailabilityForAsyncAwait()
    self.withIndentation("extension \(self.asyncClientProtocolName)", braces: .curly) {
      for (i, method) in self.service.methods.enumerated() {
        self.method = method

        let rpcType = streamingType(self.method)
        let callTypeWithoutPrefix = Types.call(for: rpcType, withGRPCPrefix: false)

        let streamsResponses = [.serverStreaming, .bidirectionalStreaming].contains(rpcType)
        let streamsRequests = [.clientStreaming, .bidirectionalStreaming].contains(rpcType)

        let sequenceProtocols = streamsRequests ? ["Sequence", "AsyncSequence"] : [nil]

        for (j, sequenceProtocol) in sequenceProtocols.enumerated() {
          // Print a new line if this is not the first function in the extension.
          if i > 0 || j > 0 {
            self.println()
          }
          let functionName = streamsRequests
            ? "\(self.methodFunctionName)<RequestStream>"
            : self.methodFunctionName
          let requestParamName = streamsRequests ? "requests" : "request"
          let requestParamType = streamsRequests ? "RequestStream" : self.methodInputName
          let returnType = streamsResponses
            ? Types.responseStream(of: self.methodOutputName)
            : self.methodOutputName
          let maybeWhereClause = sequenceProtocol.map {
            "where RequestStream: \($0), RequestStream.Element == \(self.methodInputName)"
          }
          self.printFunction(
            name: functionName,
            arguments: [
              "_ \(requestParamName): \(requestParamType)",
              "callOptions: \(Types.clientCallOptions)? = nil",
            ],
            returnType: returnType,
            access: self.access,
            async: !streamsResponses,
            throws: !streamsResponses,
            genericWhereClause: maybeWhereClause
          ) {
            self.withIndentation(
              "return\(!streamsResponses ? " try await" : "") self.perform\(callTypeWithoutPrefix)",
              braces: .round
            ) {
              self.println("path: \(self.methodPath),")
              self.println("\(requestParamName): \(requestParamName),")
              self.println("callOptions: callOptions ?? self.defaultCallOptions")
            }
          }
        }
      }
    }
  }
}

// MARK: - Client protocol implementation

extension Generator {
  internal func printAsyncServiceClientImplementation() {
    self.printAvailabilityForAsyncAwait()
    self.withIndentation(
      "\(self.access) struct \(self.asyncClientClassName): \(self.asyncClientProtocolName)",
      braces: .curly
    ) {
      self.println("\(self.access) var channel: GRPCChannel")
      self.println("\(self.access) var defaultCallOptions: CallOptions")
      self.println("\(self.access) var interceptors: \(self.clientInterceptorProtocolName)?")
      self.println()

      self.println("\(self.access) init(")
      self.withIndentation {
        self.println("channel: GRPCChannel,")
        self.println("defaultCallOptions: CallOptions = CallOptions(),")
        self.println("interceptors: \(self.clientInterceptorProtocolName)? = nil")
      }
      self.println(") {")
      self.withIndentation {
        self.println("self.channel = channel")
        self.println("self.defaultCallOptions = defaultCallOptions")
        self.println("self.interceptors = interceptors")
      }
      self.println("}")
    }
  }
}
