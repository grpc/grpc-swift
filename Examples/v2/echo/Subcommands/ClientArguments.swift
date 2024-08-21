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

import ArgumentParser
import GRPCHTTP2Core

struct ClientArguments: ParsableArguments {
  @Option(help: "The server's listening port")
  var port: Int = 1234

  @Option(help: "The number of times to repeat the call")
  var repetitions: Int = 1

  @Option(help: "Message to send to the server")
  var message: String
}

extension ClientArguments {
  var target: any ResolvableTarget {
    return .ipv4(host: "127.0.0.1", port: self.port)
  }
}
