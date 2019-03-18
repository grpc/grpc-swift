import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

/// Protocol declaring a minimum set of properties exposed by *all* types of call contexts.
public protocol ServerCallContext: class {
  /// The event loop this call is served on.
  var eventLoop: EventLoop { get }

  /// Generic metadata provided with this request.
  var request: HTTPRequestHead { get }
}

/// Base class providing data provided to the framework user for all server calls.
open class ServerCallContextBase: ServerCallContext {
  public let eventLoop: EventLoop
  public let request: HTTPRequestHead

  public init(eventLoop: EventLoop, request: HTTPRequestHead) {
    self.eventLoop = eventLoop
    self.request = request
  }
}
