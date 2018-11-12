//
// DO NOT EDIT.
//
// Generated by the protocol buffer compiler.
// Source: echo.proto
//

//
// Copyright 2018, gRPC Authors All rights reserved.
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
//
import Foundation
import Dispatch
import NIO
import NIOHTTP1
import SwiftGRPCNIO
import SwiftProtobuf


/// To build a server, implement a class that conforms to this protocol.
internal protocol Echo_EchoProvider_NIO: CallHandlerProvider {
  func get(request: Echo_EchoRequest, handler: UnaryCallHandler<Echo_EchoRequest, Echo_EchoResponse>)
  func expand(request: Echo_EchoRequest, handler: ServerStreamingCallHandler<Echo_EchoRequest, Echo_EchoResponse>)
  func collect(handler: ClientStreamingCallHandler<Echo_EchoRequest, Echo_EchoResponse>) -> (StreamEvent<Echo_EchoRequest>) -> Void
  func update(handler: BidirectionalStreamingCallHandler<Echo_EchoRequest, Echo_EchoResponse>) -> (StreamEvent<Echo_EchoRequest>) -> Void
}

extension Echo_EchoProvider_NIO {
  internal var serviceName: String { return "echo.Echo" }

  /// Determines, calls and returns the appropriate request handler, depending on the request's method.
  /// Returns nil for methods not handled by this service.
  internal func handleMethod(_ methodName: String, headers: HTTPRequestHead, serverHandler: GRPCChannelHandler, ctx: ChannelHandlerContext) -> GRPCCallHandler? {
    switch methodName {
    case "Get":
      return UnaryCallHandler(eventLoop: ctx.eventLoop, headers: headers) { handler in
        return { request in
          self.get(request: request, handler: handler)
        }
      }

    case "Expand":
      return ServerStreamingCallHandler(eventLoop: ctx.eventLoop, headers: headers) { handler in
        return { request in
          self.expand(request: request, handler: handler)
        }
      }

    case "Collect":
      return ClientStreamingCallHandler(eventLoop: ctx.eventLoop, headers: headers) { handler in
        return self.collect(handler: handler)
      }

    case "Update":
      return BidirectionalStreamingCallHandler(eventLoop: ctx.eventLoop, headers: headers) { handler in
        return self.update(handler: handler)
      }

    default: return nil
    }
  }
}

