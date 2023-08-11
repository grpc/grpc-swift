/*
 * Copyright 2020, gRPC Authors All rights reserved.
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
#if canImport(NIOSSL)
import Dispatch
import EchoImplementation
import EchoModel
import Foundation
import GRPC
import GRPCSampleData
import NIOCore
import NIOSSL
import NIOTransportServices
import XCTest

final class ZeroLengthWriteTests: GRPCTestCase {
  func clientBuilder(
    group: EventLoopGroup,
    secure: Bool,
    debugInitializer: @escaping GRPCChannelInitializer
  ) -> ClientConnection.Builder {
    if secure {
      return ClientConnection.usingTLSBackedByNIOSSL(on: group)
        .withTLS(trustRoots: .certificates([SampleCertificate.ca.certificate]))
        .withDebugChannelInitializer(debugInitializer)
    } else {
      return ClientConnection.insecure(group: group)
        .withDebugChannelInitializer(debugInitializer)
    }
  }

  func serverBuilder(
    group: EventLoopGroup,
    secure: Bool,
    debugInitializer: @escaping @Sendable (Channel) -> EventLoopFuture<Void>
  ) -> Server.Builder {
    if secure {
      return Server.usingTLSBackedByNIOSSL(
        on: group,
        certificateChain: [SampleCertificate.server.certificate],
        privateKey: SamplePrivateKey.server
      ).withTLS(trustRoots: .certificates([SampleCertificate.ca.certificate]))
        .withDebugChannelInitializer(debugInitializer)
    } else {
      return Server.insecure(group: group)
        .withDebugChannelInitializer(debugInitializer)
    }
  }

  func makeServer(
    group: EventLoopGroup,
    secure: Bool,
    debugInitializer: @escaping @Sendable (Channel) -> EventLoopFuture<Void>
  ) throws -> Server {
    return try self.serverBuilder(group: group, secure: secure, debugInitializer: debugInitializer)
      .withServiceProviders([self.makeEchoProvider()])
      .withLogger(self.serverLogger)
      .bind(host: "127.0.0.1", port: 0)
      .wait()
  }

  func makeClientConnection(
    group: EventLoopGroup,
    secure: Bool,
    port: Int,
    debugInitializer: @escaping GRPCChannelInitializer
  ) throws -> ClientConnection {
    return self.clientBuilder(group: group, secure: secure, debugInitializer: debugInitializer)
      .withBackgroundActivityLogger(self.clientLogger)
      .withConnectionReestablishment(enabled: false)
      .connect(host: "127.0.0.1", port: port)
  }

  func makeEchoProvider() -> Echo_EchoProvider { return EchoProvider() }

  func makeEchoClient(
    group: EventLoopGroup,
    secure: Bool,
    port: Int,
    debugInitializer: @escaping GRPCChannelInitializer
  ) throws -> Echo_EchoNIOClient {
    return Echo_EchoNIOClient(
      channel: try self.makeClientConnection(
        group: group,
        secure: secure,
        port: port,
        debugInitializer: debugInitializer
      ),
      defaultCallOptions: self.callOptionsWithLogger
    )
  }

  func debugPipelineExpectation(
    _ callback: @escaping @Sendable (Result<NIOFilterEmptyWritesHandler, Error>) throws -> Void
  ) -> @Sendable (Channel) -> EventLoopFuture<Void> {
    return { channel in
      channel.pipeline.handler(type: NIOFilterEmptyWritesHandler.self).always { result in
        do {
          try callback(result)
        } catch {
          XCTFail("Unexpected error: \(error)")
        }
      }.map { _ in () }.recover { _ in () }
    }
  }

  private func _runTest(
    networkPreference: NetworkPreference,
    secure: Bool,
    clientHandlerCallback: @escaping @Sendable (Result<NIOFilterEmptyWritesHandler, Error>) throws
      -> Void,
    serverHandlerCallback: @escaping @Sendable (Result<NIOFilterEmptyWritesHandler, Error>) throws
      -> Void
  ) {
    // We can only run this test on platforms where the zero-length write workaround _could_ be added.
    #if canImport(Network)
    guard #available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) else { return }
    let group = PlatformSupport.makeEventLoopGroup(
      loopCount: 1,
      networkPreference: networkPreference
    )
    let server = try! self.makeServer(
      group: group,
      secure: secure,
      debugInitializer: self.debugPipelineExpectation(serverHandlerCallback)
    )

    defer {
      XCTAssertNoThrow(try server.close().wait())
      XCTAssertNoThrow(try group.syncShutdownGracefully())
    }

    let port = server.channel.localAddress!.port!
    let client = try! self.makeEchoClient(
      group: group,
      secure: secure,
      port: port,
      debugInitializer: self.debugPipelineExpectation(clientHandlerCallback)
    )
    defer {
      XCTAssertNoThrow(try client.channel.close().wait())
    }

    // We need to wait here to confirm that the RPC completes. All expectations should have completed by then.
    let call = client.get(Echo_EchoRequest(text: "foo bar baz"))
    XCTAssertNoThrow(try call.status.wait())
    #endif
  }

  func testZeroLengthWriteTestPosixSecure() throws {
    // We can only run this test on platforms where the zero-length write workaround _could_ be added.
    #if canImport(Network)
    guard #available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) else { return }

    self._runTest(
      networkPreference: .userDefined(.posix),
      secure: true,
      clientHandlerCallback: { result in
        XCTAssertThrowsError(try result.get())
      },
      serverHandlerCallback: { result in
        XCTAssertThrowsError(try result.get())
      }
    )
    #endif
  }

  func testZeroLengthWriteTestPosixInsecure() throws {
    // We can only run this test on platforms where the zero-length write workaround _could_ be added.
    #if canImport(Network)
    guard #available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) else { return }

    self._runTest(
      networkPreference: .userDefined(.posix),
      secure: false,
      clientHandlerCallback: { result in
        XCTAssertThrowsError(try result.get())
      },
      serverHandlerCallback: { result in
        XCTAssertThrowsError(try result.get())
      }
    )
    #endif
  }

  func testZeroLengthWriteTestNetworkFrameworkSecure() throws {
    // We can only run this test on platforms where the zero-length write workaround _could_ be added.
    #if canImport(Network)
    guard #available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) else { return }

    self._runTest(
      networkPreference: .userDefined(.networkFramework),
      secure: true,
      clientHandlerCallback: { result in
        XCTAssertThrowsError(try result.get())
      },
      serverHandlerCallback: { result in
        XCTAssertThrowsError(try result.get())
      }
    )
    #endif
  }

  func testZeroLengthWriteTestNetworkFrameworkInsecure() throws {
    // We can only run this test on platforms where the zero-length write workaround _could_ be added.
    #if canImport(Network)
    guard #available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) else { return }

    self._runTest(
      networkPreference: .userDefined(.networkFramework),
      secure: false,
      clientHandlerCallback: { result in
        XCTAssertNoThrow(try result.get())
      },
      serverHandlerCallback: { result in
        XCTAssertNoThrow(try result.get())
      }
    )
    #endif
  }
}

#endif // canImport(NIOSSL)
