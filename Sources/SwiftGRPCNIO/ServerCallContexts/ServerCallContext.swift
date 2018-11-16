import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

open class ServerCallContext {
  public let eventLoop: EventLoop
  
  public let headers: HTTPRequestHead
  
  public init(eventLoop: EventLoop, headers: HTTPRequestHead) {
    self.eventLoop = eventLoop
    self.headers = headers
  }
}
