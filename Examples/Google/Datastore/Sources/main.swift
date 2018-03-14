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
import Commander
import Dispatch
import Foundation
import SwiftGRPC
import OAuth2

// Convert Encodable objects to dictionaries of property-value pairs.
class PropertiesEncoder {
  static func encode<T: Encodable>(_ value: T) throws -> [String: Any]? {
    #if os(OSX)
      let plist = try PropertyListEncoder().encode(value)
      let properties = try PropertyListSerialization.propertyList(from: plist, options: [], format: nil)
    #else
      let data = try JSONEncoder().encode(value)
      let properties = try JSONSerialization.jsonObject(with: data, options: [])
    #endif
    return properties as? [String: Any]
  }
}

// Create Decodable objects from dictionaries of property-value pairs.
class PropertiesDecoder {
  static func decode<T: Decodable>(_ type: T.Type, from: [String: Any]) throws -> T {
    #if os(OSX)
      let plist = try PropertyListSerialization.data(fromPropertyList: from, format: .binary, options: 0)
      return try PropertyListDecoder().decode(type, from: plist)
    #else
      let data = try JSONSerialization.data(withJSONObject: from, options: [])
      return try JSONDecoder().decode(type, from: data)
    #endif
  }
}

// a Swift interface to the Google Cloud Datastore API
class Datastore {
  var projectID: String
  var service: Google_Datastore_V1_DatastoreServiceClient!

  let scopes = ["https://www.googleapis.com/auth/datastore"]

  init(projectID: String) {
    self.projectID = projectID
  }

  func authenticate() throws {
    var authToken: String!
    if let provider = DefaultTokenProvider(scopes: scopes) {
      let sem = DispatchSemaphore(value: 0)
      try provider.withToken { (token, _) -> Void in
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
    service = Google_Datastore_V1_DatastoreServiceClient(address: "datastore.googleapis.com")
    service.metadata = Metadata(["authorization": "Bearer " + authToken])
  }

  func performList<T: Codable>(type: T.Type) throws -> [Int64: T] {
    var request = Google_Datastore_V1_RunQueryRequest()
    request.projectID = projectID
    var query = Google_Datastore_V1_GqlQuery()
    query.queryString = "select * from " + String(describing: type)
    request.gqlQuery = query
    let result = try service.runquery(request)
    var entities: [Int64: T] = [:]
    for entityResult in result.batch.entityResults {
      var properties: [String: Any] = [:]
      for property in entityResult.entity.properties {
        let key = property.key
        switch property.value.valueType! {
        case .integerValue(let v):
          properties[key] = v
        case .stringValue(let v):
          properties[key] = v
        default:
          print("?")
        }
      }
      let entity = try PropertiesDecoder.decode(type, from: properties)
      entities[entityResult.entity.key.path[0].id] = entity
    }
    return entities
  }

  func performInsert<T: Codable>(thing: T) throws {
    var request = Google_Datastore_V1_CommitRequest()
    request.projectID = projectID
    request.mode = .nonTransactional
    var pathElement = Google_Datastore_V1_Key.PathElement()
    pathElement.kind = String(describing: type(of: thing))
    var key = Google_Datastore_V1_Key()
    key.path = [pathElement]
    var entity = Google_Datastore_V1_Entity()
    entity.key = key
    let properties = try PropertiesEncoder.encode(thing)!
    for (k, v) in properties {
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
    for mutationResult in result.mutationResults {
      print("\(mutationResult)")
    }
  }

  func performDelete(kind: String,
                     id: Int64) throws {
    var request = Google_Datastore_V1_CommitRequest()
    request.projectID = projectID
    request.mode = .nonTransactional
    var pathElement = Google_Datastore_V1_Key.PathElement()
    pathElement.kind = kind
    pathElement.id = id
    var key = Google_Datastore_V1_Key()
    key.path = [pathElement]
    var mutation = Google_Datastore_V1_Mutation()
    mutation.delete = key
    request.mutations.append(mutation)
    let result = try service.commit(request)
    for mutationResult in result.mutationResults {
      print("\(mutationResult)")
    }
  }
}

let projectID = "your-project-identifier"

struct Thing: Codable {
  var name: String
  var number: Int
}

Group {
  $0.command("insert") { (number: Int) in
    let datastore = Datastore(projectID: projectID)
    try datastore.authenticate()
    let thing = Thing(name: "Thing", number: number)
    try datastore.performInsert(thing: thing)
  }

  $0.command("delete") { (id: Int) in
    let datastore = Datastore(projectID: projectID)
    try datastore.authenticate()
    try datastore.performDelete(kind: "Thing", id: Int64(id))
  }

  $0.command("list") {
    let datastore = Datastore(projectID: projectID)
    try datastore.authenticate()
    let entities = try datastore.performList(type: Thing.self)
    print("\(entities)")
  }

}.run()
