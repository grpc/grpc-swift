/*
 * Copyright 2016, gRPC Authors All rights reserved.
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
import Cocoa
import gRPC

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_: Notification) {
    gRPC.initialize()
    print("GRPC version", gRPC.version())
  }

  func applicationWillTerminate(_: Notification) {
    // We don't call shutdown() here because we can't be sure that
    // any running server queues will have stopped by the time this is
    // called. If one is still running after we call shutdown(), the
    // program will crash.
    // gRPC.shutdown()
  }
}
