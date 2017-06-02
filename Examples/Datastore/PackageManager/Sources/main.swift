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

gRPC.initialize()

let authToken = "<YOUR AUTH TOKEN>"

let projectID = "<YOUR PROJECT ID>"

let certificateURL = URL(fileURLWithPath:"roots.pem")
let certificates = try! String(contentsOf: certificateURL)
let service = Google_Datastore_V1_DatastoreService(address:"datastore.googleapis.com",
                               certificates:certificates,
                               host:nil)

service.metadata = Metadata(["authorization":"Bearer " + authToken])

var request = Google_Datastore_V1_RunQueryRequest()
request.projectId = projectID

var query = Google_Datastore_V1_GqlQuery()
query.queryString = "select *"

request.gqlQuery = query

print("\(request)")

let result = try service.runquery(request)

print("\(result)")
