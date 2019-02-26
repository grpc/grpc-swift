import Foundation
import NIO
import NIOHTTP1
import NIOHTTP2

/// Channel handler that creates different processing pipelines depending on whether
/// the incoming request is HTTP 1 or 2.
public class HTTPProtocolSwitcher {
  private let handlersInitializer: ((Channel) -> EventLoopFuture<Void>)

  public init(handlersInitializer: (@escaping (Channel) -> EventLoopFuture<Void>)) {
    self.handlersInitializer = handlersInitializer
  }
}

extension HTTPProtocolSwitcher: ChannelInboundHandler {
  public typealias InboundIn = ByteBuffer
  public typealias InboundOut = ByteBuffer

  enum HTTPProtocolVersionError: Error {
    /// Raised when it wasn't possible to detect HTTP Protocol version.
    case invalidHTTPProtocolVersion

    var localizedDescription: String {
      switch self {
      case .invalidHTTPProtocolVersion:
        return "Could not identify HTTP Protocol Version"
      }
    }
  }

  /// HTTP Protocol Version type
  enum HTTPProtocolVersion {
    case http1
    case http2
  }

  public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
    // Detect the HTTP protocol version for the incoming request, or error out if it
    // couldn't be detected.
    var inBuffer = unwrapInboundIn(data)
    guard let initialData = inBuffer.readString(length: inBuffer.readableBytes),
          let preamble = initialData.split(separator: "\r\n",
                                           maxSplits: 1,
                                           omittingEmptySubsequences: true).first,
          let version = protocolVersion(String(preamble)) else {

      ctx.fireErrorCaught(HTTPProtocolVersionError.invalidHTTPProtocolVersion)
      return
    }

    // Depending on whether it is HTTP1 or HTTP2, created different processing pipelines.
    // Inbound handlers in handlersInitializer should expect HTTPServerRequestPart objects
    // and outbound handlers should return HTTPServerResponsePart objects.
    switch version {
    case .http1:
      // Upgrade connections are not handled since gRPC connections already arrive in HTTP2,
      // while gRPC-Web does not support HTTP2 at all, so there are no compelling use cases
      // to support this.
      _ = ctx.pipeline.configureHTTPServerPipeline(withErrorHandling: true)
        .then { ctx.pipeline.add(handler: WebCORSHandler()) }
        .then { (Void) -> EventLoopFuture<Void> in self.handlersInitializer(ctx.channel) }
    case .http2:
      _ = ctx.pipeline.add(handler: HTTP2Parser(mode: .server))
        .then { () -> EventLoopFuture<Void> in
          let multiplexer = HTTP2StreamMultiplexer { (channel, streamID) -> EventLoopFuture<Void> in
            return channel.pipeline.add(handler: HTTP2ToHTTP1ServerCodec(streamID: streamID))
              .then { (Void) -> EventLoopFuture<Void> in self.handlersInitializer(channel) }
          }
          return ctx.pipeline.add(handler: multiplexer)
        }
    }

    ctx.fireChannelRead(data)
    _ = ctx.pipeline.remove(ctx: ctx)
  }

  /// Peek into the first line of the packet to check which HTTP version is being used.
  private func protocolVersion(_ preamble: String) -> HTTPProtocolVersion? {
    let range = NSRange(location: 0, length: preamble.utf16.count)
    let regex = try! NSRegularExpression(pattern: "^.*HTTP/(\\d)\\.\\d$")
    let result = regex.firstMatch(in: preamble, options: [], range: range)!

    let versionRange = result.range(at: 1)
    let start = String.UTF16Index(encodedOffset: versionRange.location)
    let end = String.UTF16Index(encodedOffset: versionRange.location + versionRange.length)

    switch String(preamble.utf16[start..<end])! {
    case "1":
      return .http1
    case "2":
      return .http2
    default:
      return nil
    }
  }
}
