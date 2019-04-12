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
import Foundation
import SwiftGRPCNIO
import NIO
import NIOHTTP1

public protocol InteroperabilityTest {
  /// Run a test case using the given connection.
  ///
  /// The test case is considered unsuccessful if any exception is thrown, conversely if no
  /// exceptions are thrown it is successful.
  ///
  /// - Parameter connection: The connection to use for the test.
  /// - Throws: Any exception may be thrown to indicate an unsuccessful test.
  func run(using connection: GRPCClientConnection) throws
}
