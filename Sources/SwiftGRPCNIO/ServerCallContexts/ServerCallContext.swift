import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

// Base class providing data provided to the framework user for all server calls.
open class ServerCallContext {
  public let eventLoop: EventLoop
  public let headers: HTTPRequestHead
  
  public init(eventLoop: EventLoop, headers: HTTPRequestHead) {
    self.eventLoop = eventLoop
    self.headers = headers
  }
}
