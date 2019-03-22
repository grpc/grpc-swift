import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

/// Base class providing data provided to the framework user for all server calls.
open class ServerCallContext {
  /// The event loop this call is served on.
  public let eventLoop: EventLoop
  /// Generic metadata provided with this request.
  public let request: HTTPRequestHead
  
  public init(eventLoop: EventLoop, request: HTTPRequestHead) {
    self.eventLoop = eventLoop
    self.request = request
  }
}
