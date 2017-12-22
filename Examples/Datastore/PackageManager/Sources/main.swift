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

let projectID = "your-project-identifier"
let scopes = ["https://www.googleapis.com/auth/datastore"]

struct Thing : Codable {
  var name: String
  var number: Int
}

class PropertiesEncoder {
  static func encode<T : Encodable>(_ value : T) throws -> [String:Any]? {
    let plist = try PropertyListEncoder().encode(value)
    let properties = try PropertyListSerialization.propertyList(from:plist, options:[], format:nil)
    return properties as? [String:Any]
  }
}

class PropertiesDecoder {
  static func decode<T: Decodable>(_ type: T.Type, from: [String:Any]) throws -> T {
    let plist = try PropertyListSerialization.data(fromPropertyList: from,
                                                   format: .binary, options:0)
    return try PropertyListDecoder().decode(type, from: plist)
  }
}

func runSelectQuery(service: Google_Datastore_V1_DatastoreService) throws {
  var request = Google_Datastore_V1_RunQueryRequest()
  request.projectID = projectID
  var query = Google_Datastore_V1_GqlQuery()
  query.queryString = "select *"
  request.gqlQuery = query
  print("\(request)")
  let result = try service.runquery(request)
  print("\(result)")
}

func runInsert(service: Google_Datastore_V1_DatastoreService) throws {
  var request = Google_Datastore_V1_CommitRequest()
  request.projectID = projectID
  request.mode = .nonTransactional

  var pathElement = Google_Datastore_V1_Key.PathElement()
  pathElement.kind = "Thing"
  var key = Google_Datastore_V1_Key()
  key.path = [pathElement]
  var entity = Google_Datastore_V1_Entity()
  entity.key = key

  let thing = Thing(name:"Thing", number:1)
  let properties = try PropertiesEncoder.encode(thing)!
  for (k,v) in properties {
    var value = Google_Datastore_V1_Value()
    switch v {
    case let v as String:
      value.stringValue = v
    case let v as Int:
      value.integerValue = Int64(v)
    default:
      break
    }
    entity.properties[k] = value
  }

  var mutation = Google_Datastore_V1_Mutation()
  mutation.insert = entity

  request.mutations.append(mutation)

  let result = try service.commit(request)
  print("\(result)")
}

func main() throws {
  // Get an OAuth token
  var authToken : String!
  if let provider = DefaultTokenProvider(scopes:scopes) {
    let sem = DispatchSemaphore(value: 0)
    try provider.withToken() {(token, error) -> Void in
      if let token = token {
        authToken = token.AccessToken
      }
      sem.signal()
    }
    sem.wait()
  }
  if authToken == nil {
    print("ERROR: No OAuth token is available. Did you set GOOGLE_APPLICATION_CREDENTIALS?")
    exit(-1)
  }
  // Initialize gRPC service
  gRPC.initialize()
  let certificateURL = URL(fileURLWithPath:"/roots.pem")
  let certificates = try! String(contentsOf: certificateURL, encoding: .utf8)
  let service = Google_Datastore_V1_DatastoreService(address:"datastore.googleapis.com",
                                                     certificates:certificates,
                                                     host:nil)
  service.metadata = Metadata(["authorization":"Bearer " + authToken])
  // Run some queries
  try runInsert(service:service)
  try runSelectQuery(service:service)
}

do {
  try main()
} catch (let error) {
  print("ERROR: \(error)")
}
