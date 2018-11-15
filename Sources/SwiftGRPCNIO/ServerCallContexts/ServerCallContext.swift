import Foundation
import SwiftProtobuf
import NIO
import NIOHTTP1

open class ServerCallContext<ResponseMessage: Message> {
  public typealias WrappedResponse = GRPCServerResponsePart<ResponseMessage>
  
  public let eventLoop: EventLoop
  
  public let headers: HTTPRequestHead
  
  public internal(set) var ctx: ChannelHandlerContext?
  
  public init(eventLoop: EventLoop, headers: HTTPRequestHead) {
    self.eventLoop = eventLoop
    self.headers = headers
  }
}
