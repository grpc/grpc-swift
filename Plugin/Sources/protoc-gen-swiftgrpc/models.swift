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
import SwiftProtobuf
import SwiftProtobufPluginLibrary
import Stencil
import PathKit

struct FileDescriptor {
  var name : String
  var package : String
  var service: [ServiceDescriptor] = []

  init(proto: Google_Protobuf_FileDescriptorProto) {
    name = proto.name
    package = proto.package
    for service in proto.service {
      self.service.append(ServiceDescriptor(proto:service))
    }
  }
}

struct ServiceDescriptor {
  var name : String
  var method : [MethodDescriptor] = []

  init(proto: Google_Protobuf_ServiceDescriptorProto) {
    name = proto.name
    for method in proto.method {
      self.method.append(MethodDescriptor(proto:method))
    }
  }
}

struct MethodDescriptor {
  var name : String
  var inputType : String
  var outputType : String
  var clientStreaming : Bool
  var serverStreaming : Bool

  init(proto: Google_Protobuf_MethodDescriptorProto) {
    name = proto.name
    inputType = proto.inputType
    outputType = proto.outputType
    clientStreaming = proto.clientStreaming
    serverStreaming = proto.serverStreaming
  }
}

