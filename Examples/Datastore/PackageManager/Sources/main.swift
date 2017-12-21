/*
 * Copyright 2017, gRPC Authors All rights reserved.
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
import Foundation
import gRPC
import OAuth2

let CREDENTIALS = "google.json" // in $HOME/.credentials
let TOKEN = "google.json" // local auth token storage

#if os(OSX)
// On OS X, we use the local browser to help the user get a token.
let tokenProvider = try BrowserTokenProvider(credentials:CREDENTIALS, token:TOKEN)
guard let tokenProvider = tokenProvider else {
  print("ERROR: Unable to create BrowserTokenProvider.")
  exit(-1)
}
if tokenProvider.token == nil {
  try tokenProvider.signIn(scopes:["https://www.googleapis.com/auth/datastore"]) 
  try tokenProvider.saveToken(TOKEN)
}
#else
// On Linux, we can get a token if we are running in Google Cloud Shell
// or in some other Google Cloud instance (GAE, GKE, GCE, etc).
let tokenProvider = try GoogleTokenProvider()
#endif

gRPC.initialize()

guard let authToken = tokenProvider.token?.AccessToken else {
  print("ERROR: No OAuth token is available.")
  exit(-1)
}

let projectID = "your-project-identifier"

let certificateURL = URL(fileURLWithPath:"roots.pem")
let certificates = try! String(contentsOf: certificateURL, encoding: .utf8)
let service = Google_Datastore_V1_DatastoreService(address:"datastore.googleapis.com",
                                                   certificates:certificates,
                                                   host:nil)

service.metadata = Metadata(["authorization":"Bearer " + authToken])

var request = Google_Datastore_V1_RunQueryRequest()
request.projectID = projectID

var query = Google_Datastore_V1_GqlQuery()
query.queryString = "select *"

request.gqlQuery = query

print("\(request)")

do {
  let result = try service.runquery(request)
  print("\(result)")
} catch (let error) {
  print("ERROR: \(error)")
}
