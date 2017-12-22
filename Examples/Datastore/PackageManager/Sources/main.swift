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
import Commander

let projectID = "your-project-identifier"
let scopes = ["https://www.googleapis.com/auth/datastore"]

struct Thing : Codable {
  var name: String
  var number: Int
}

// Convert Encodable objects to dictionaries of property-value pairs.
class PropertiesEncoder {
  static func encode<T : Encodable>(_ value : T) throws -> [String:Any]? {
    let plist = try PropertyListEncoder().encode(value)
    let properties = try PropertyListSerialization.propertyList(from:plist, options:[], format:nil)
    return properties as? [String:Any]
  }
}

// Create Decodable objects from dictionaries of property-value pairs.
class PropertiesDecoder {
  static func decode<T: Decodable>(_ type: T.Type, from: [String:Any]) throws -> T {
    let plist = try PropertyListSerialization.data(fromPropertyList: from,
                                                   format: .binary, options:0)
    return try PropertyListDecoder().decode(type, from: plist)
  }
}

func prepareService() throws -> Google_Datastore_V1_DatastoreService? {
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
  let service = Google_Datastore_V1_DatastoreService(address:"datastore.googleapis.com",
                                                     certificates:nil,
                                                     host:nil)
  service.metadata = Metadata(["authorization":"Bearer " + authToken])
  return service
}

func performList(service: Google_Datastore_V1_DatastoreService) throws {
  var request = Google_Datastore_V1_RunQueryRequest()
  request.projectID = projectID
  var query = Google_Datastore_V1_GqlQuery()
  query.queryString = "select * from Thing"
  request.gqlQuery = query
  let result = try service.runquery(request)
  var entities : [Int64 : Thing] = [:]
  for entityResult in result.batch.entityResults {
    var properties : [String:Any] = [:]
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
    let entity = try PropertiesDecoder.decode(Thing.self, from:properties)
    entities[entityResult.entity.key.path[0].id] = entity
  }
  print("\(entities)")
}

func performInsert(service: Google_Datastore_V1_DatastoreService,
               number: Int) throws {
  var request = Google_Datastore_V1_CommitRequest()
  request.projectID = projectID
  request.mode = .nonTransactional
  var pathElement = Google_Datastore_V1_Key.PathElement()
  pathElement.kind = "Thing"
  var key = Google_Datastore_V1_Key()
  key.path = [pathElement]
  var entity = Google_Datastore_V1_Entity()
  entity.key = key
  let thing = Thing(name:"Thing", number:number)
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
  for mutationResult in result.mutationResults {
    print("\(mutationResult)")
  }
}

func performDelete(service: Google_Datastore_V1_DatastoreService,
               kind: String,
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

Group {
  $0.command("insert") { (number:Int) in
    if let service = try prepareService() {
      try performInsert(service:service, number:number)
    }
  }

  $0.command("delete") { (id:Int) in
    if let service = try prepareService() {
      try performDelete(service:service, kind:"Thing", id:Int64(id))
    }
  }
  
  $0.command("list") {
    if let service = try prepareService() {
      try performList(service:service)
    }
  }
  
  }.run()

