/*
 * Copyright 2024, gRPC Authors All rights reserved.
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
enum ContentType {
  case protobuf

  init?(value: String) {
    switch value {
    case "application/grpc",
      "application/grpc+proto":
      self = .protobuf

    default:
      return nil
    }
  }

  var canonicalValue: String {
    switch self {
    case .protobuf:
      // This is more widely supported than "application/grpc+proto"
      return "application/grpc"
    }
  }
}
