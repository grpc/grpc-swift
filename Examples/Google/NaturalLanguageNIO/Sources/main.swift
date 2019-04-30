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
import SwiftGRPCNIO
import OAuth2
import NIO
import NIOHTTP1
import NIOSSL

/// Prepare a TLSMode for a general SSL client that supports HTTP/2.
func makeClientTLS() throws -> GRPCClientConnection.TLSMode {
  let configuration = TLSConfiguration.forClient(applicationProtocols: ["h2"])
  let context = try NIOSSLContext(configuration: configuration)
  return .custom(context)
}

/// Create a client and return a future to provide its value.
func makeServiceClient(_ eventLoopGroup: MultiThreadedEventLoopGroup,
                       address: String,
                       port: Int)
  -> EventLoopFuture<Google_Cloud_Language_V1_LanguageServiceService_NIOClient> {
    let promise = eventLoopGroup.next().makePromise(of: Google_Cloud_Language_V1_LanguageServiceService_NIOClient.self)
    do {
      try GRPCClientConnection.start(host: address,
                                     port: port,
                                     eventLoopGroup: eventLoopGroup,
                                     tls: makeClientTLS())
        .map { client in
          promise.succeed(Google_Cloud_Language_V1_LanguageServiceService_NIOClient(connection: client))
        }
        .wait()
    } catch {
      promise.fail(error)
    }
    return promise.futureResult
}

enum AuthError: Error {
  case tokenProviderFailed
  case noTokenProvider
}

/// Get an auth token and return a future to provide its value.
func getAuthToken(_ eventLoop: EventLoop,
                  scopes: [String])
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
  let authToken = try getAuthToken(eventLoopGroup.next(), scopes: scopes).wait()

  // Create a service client.
  let service = try makeServiceClient(
    eventLoopGroup,
    address: "language.googleapis.com",
    port: 443).wait()

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
