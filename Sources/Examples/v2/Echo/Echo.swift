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

@main
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
struct Echo: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "echo",
    abstract: "A multi-tool to run an echo server and execute RPCs against it.",
    subcommands: [Serve.self, Get.self, Collect.self, Expand.self, Update.self]
  )
}
