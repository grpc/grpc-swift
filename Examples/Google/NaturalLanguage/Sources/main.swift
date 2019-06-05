/*
 * Copyright 2019, gRPC Authors All rights reserved.
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
import Dispatch
import Foundation
import GRPC
import OAuth2
import NIO
import NIOHTTP1
import NIOSSL

/// Prepare an SSL context for a general SSL client that supports HTTP/2.
func makeClientTLS() throws -> NIOSSLContext {
  let configuration = TLSConfiguration.forClient(applicationProtocols: ["h2"])
  return try NIOSSLContext(configuration: configuration)
}

/// Create a client and return a future to provide its value.
func makeServiceClient(host: String,
                       port: Int,
                       eventLoopGroup: MultiThreadedEventLoopGroup)
  -> EventLoopFuture<Google_Cloud_Language_V1_LanguageServiceServiceClient> {
    let promise = eventLoopGroup.next().makePromise(of: Google_Cloud_Language_V1_LanguageServiceServiceClient.self)
    do {
      let configuration = GRPCClientConnection.Configuration(
        target: .hostAndPort(host, port),
        eventLoopGroup: eventLoopGroup,
        tlsConfiguration: .init(sslContext: try makeClientTLS())

      try GRPCClientConnection.start(configuration)
        .map { client in
          Google_Cloud_Language_V1_LanguageServiceServiceClient(connection: client)
        }.cascade(to: promise)
    } catch {
      promise.fail(error)
    }
    return promise.futureResult
}

enum AuthError: Error {
  case noTokenProvider
  case tokenProviderFailed
}

/// Get an auth token and return a future to provide its value.
func getAuthToken(scopes: [String],
                  eventLoop: EventLoop)
  -> EventLoopFuture<String> {
    let promise = eventLoop.makePromise(of: String.self)
    guard let provider = DefaultTokenProvider(scopes: scopes) else {
      promise.fail(AuthError.noTokenProvider)
      return promise.futureResult
    }
    do {
      try provider.withToken { (token, error) in
        if let token = token,
          let accessToken = token.AccessToken {
          promise.succeed(accessToken)
        } else if let error = error {
          promise.fail(error)
        } else {
          promise.fail(AuthError.tokenProviderFailed)
        }
      }
    } catch {
      promise.fail(error)
    }
    return promise.futureResult
}

/// Main program. Make a sample API request.
do {
  let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)

  // Get an auth token.
  let scopes = ["https://www.googleapis.com/auth/cloud-language"]
  let authToken = try getAuthToken(
    scopes: scopes,
    eventLoop: eventLoopGroup.next()).wait()

  // Create a service client.
  let service = try makeServiceClient(
    host: "language.googleapis.com",
    port: 443,
    eventLoopGroup: eventLoopGroup).wait()

  // Use CallOptions to send the auth token (necessary) and set a custom timeout (optional).
  let headers = HTTPHeaders([("authorization", "Bearer " + authToken)])
  let timeout = try! GRPCTimeout.seconds(30)
  let callOptions = CallOptions(customMetadata: headers, timeout: timeout)
  print("CALL OPTIONS\n\(callOptions)\n")

  // Construct the API request.
  var document = Google_Cloud_Language_V1_Document()
  document.type = .plainText
  document.content = "The Caterpillar and Alice looked at each other for some time in silence: at last the Caterpillar took the hookah out of its mouth, and addressed her in a languid, sleepy voice. `Who are you?' said the Caterpillar."

  var features = Google_Cloud_Language_V1_AnnotateTextRequest.Features()
  features.extractSyntax = true
  features.extractEntities = true
  features.extractDocumentSentiment = true
  features.extractEntitySentiment = true
  features.classifyText = true

  var request = Google_Cloud_Language_V1_AnnotateTextRequest()
  request.document = document
  request.features = features
  print("REQUEST MESSAGE\n\(request)")

  // Create/start the API call.
  let call = service.annotateText(request, callOptions: callOptions)
  call.response.whenSuccess { response in
    print("CALL SUCCEEDED WITH RESPONSE\n\(response)")
  }
  call.response.whenFailure { error in
    print("CALL FAILED WITH ERROR\n\(error)")
  }

  // wait() on the status to stop the program from exiting.
  let status = try call.status.wait()
  print("CALL STATUS\n\(status)")
} catch {
  print("EXAMPLE FAILED WITH ERROR\n\(error)")
}
