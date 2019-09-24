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

// See:
// - https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-HTTP2.md
// - https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-WEB.md
internal enum ContentType {
  case protobuf
  case webProtobuf
  case webTextProtobuf

  init?(value: String) {
    switch value {
    case "application/grpc",
         "application/grpc+proto":
      self = .protobuf

    case "application/grpc-web",
         "application/grpc-web+proto":
      self = .webProtobuf

    case "application/grpc-web-text",
         "application/grpc-web-text+proto":
      self = .webTextProtobuf

    default:
      return nil
    }
  }

  var canonicalValue: String {
    switch self {
    case .protobuf:
      return "application/grpc+proto"

    case .webProtobuf:
      return "application/grpc-web+proto"

    case .webTextProtobuf:
      return "application/grpc-web-text+proto"
    }
  }
}
