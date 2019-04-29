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

func makeClientTLS() throws -> GRPCClientConnection.TLSMode {
  let configuration = TLSConfiguration.forClient(applicationProtocols: ["h2"])
  let context = try NIOSSLContext(configuration: configuration)
  return .custom(context)
}

let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)

/// Create a client and wait for it to initialize. Returns nil if initialisation fails.
func makeServiceClient(address: String, port: Int) -> Google_Cloud_Language_V1_LanguageServiceService_NIOClient? {
  do {
    return try GRPCClientConnection.start(host: address,
                                          port: port,
                                          eventLoopGroup: eventLoopGroup,
                                          tls: makeClientTLS())
      .map { client in
        Google_Cloud_Language_V1_LanguageServiceService_NIOClient(connection: client)
      }
      .wait()
  } catch {
    print("Unable to create a client: \(error)")
    return nil
  }
}

enum AuthError: Error {
  case providerFailed
  case noProvider
}

func getAuthToken(_ eventLoopGroup: MultiThreadedEventLoopGroup,
                  scopes: [String]) -> EventLoopFuture<String> {
  let promise = eventLoopGroup.next().makePromise(of: String.self)
  if let provider = DefaultTokenProvider(scopes: scopes) {
    do {
      try provider.withToken { (token, error) in
        if let token = token,
          let accessToken = token.AccessToken {
          promise.succeed(accessToken)
        } else {
          if let error = error {
            promise.fail(error)
          } else {
            promise.fail(AuthError.providerFailed)
          }
        }
      }
    }
    catch {
      promise.fail(AuthError.providerFailed)
    }
  } else {
    promise.fail(AuthError.noProvider)
  }
  return promise.futureResult
}

let scopes = ["https://www.googleapis.com/auth/cloud-language"]
guard let authToken = try? getAuthToken(eventLoopGroup, scopes: scopes).wait()
  else {
    print("ERROR: No OAuth token is available.")
    exit(-1)
}

print("my token: \(authToken)")

guard let service = makeServiceClient(
  address: "language.googleapis.com",
  port: 443)
  else {
    print("ERROR: Unable to create service client.")
    exit(-1)
}

let headers = HTTPHeaders([("authorization", "Bearer " + authToken)])
let callOptions = CallOptions(customMetadata: headers,
                              timeout: try! GRPCTimeout.seconds(30))

var request = Google_Cloud_Language_V1_AnnotateTextRequest()

var document = Google_Cloud_Language_V1_Document()
document.type = .plainText
document.content = "The Caterpillar and Alice looked at each other for some time in silence: at last the Caterpillar took the hookah out of its mouth, and addressed her in a languid, sleepy voice. `Who are you?' said the Caterpillar."
request.document = document

var features = Google_Cloud_Language_V1_AnnotateTextRequest.Features()
features.extractSyntax = true
features.extractEntities = true
features.extractDocumentSentiment = true
features.extractEntitySentiment = true
features.classifyText = true
request.features = features

print("headers: \(headers)")
print("request: \(request)")

let annotateText = service.annotateText(request, callOptions: callOptions)

annotateText.response.whenSuccess { response in
  print("annotateText received: \(response)")
}

annotateText.response.whenFailure { error in
  print("annotateText failed with error: \(error)")
}

print("running")
// wait() on the status to stop the program from exiting.
do {
  print("waiting")
  let status = try annotateText.status.wait()
  print("annotateText completed with status: \(status)")
} catch {
  print("annotateText status failed with error: \(error)")
}
