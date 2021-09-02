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

enum Types {
  static let serverContext = "GRPCAsyncServerCallContext"
  static let serverHandler = "GRPCAsyncServerHandler"

  static let clientCallOptions = "CallOptions"

  private static let unaryCall = "AsyncUnaryCall"
  private static let clientStreamingCall = "AsyncClientStreamingCall"
  private static let serverStreamingCall = "AsyncServerStreamingCall"
  private static let bidirectionalStreamingCall = "AsyncBidirectionalStreamingCall"

  static func requestStream(of type: String) -> String {
    return "GRPCAsyncRequestStream<\(type)>"
  }

  static func responseStream(of type: String) -> String {
    return "GRPCAsyncResponseStream<\(type)>"
  }

  static func responseStreamWriter(of type: String) -> String {
    return "GRPCAsyncResponseStreamWriter<\(type)>"
  }

  static func serializer(for type: String) -> String {
    return "ProtobufSerializer<\(type)>"
  }

  static func deserializer(for type: String) -> String {
    return "ProtobufDeserializer<\(type)>"
  }

  static func call(for streamingType: StreamingType, withGRPCPrefix: Bool = true) -> String {
    let typeName: String

    switch streamingType {
    case .unary:
      typeName = Types.unaryCall
    case .clientStreaming:
      typeName = Types.clientStreamingCall
    case .serverStreaming:
      typeName = Types.serverStreamingCall
    case .bidirectionalStreaming:
      typeName = Types.bidirectionalStreamingCall
    }

    if withGRPCPrefix {
      return "GRPC" + typeName
    } else {
      return typeName
    }
  }
}
