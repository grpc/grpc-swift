/*
 * Copyright 2020, gRPC Authors All rights reserved.
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
import Lifecycle
import Logging

/// Main entry point to the QPS worker application.
final class QPSWorkerApp: ParsableCommand {
  @Option(name: .customLong("driver_port"), help: "Port for communication with driver.")
  var driverPort: Int

  @Option(name: .customLong("server_port"), help: "Port for operation as a server.")
  var serverPort: Int?

  @Option(
    name: .customLong("credential_type"),
    help: "Credential type for communication with driver."
  )
  var credentialType: String = "todo" // TODO: Default to kInsecureCredentialsType

  /// Run the application and wait for completion to be signalled.
  func run() throws {
    let logger = Logger(label: "QPSWorker")

    assert({
      logger.warning("⚠️ WARNING: YOU ARE RUNNING IN DEBUG MODE ⚠️")
      return true
    }())

    logger.info("Starting...")

    logger.info("Initializing the lifecycle container")
    // This installs backtrace.
    let lifecycle = ServiceLifecycle()

    let qpsWorker = QPSWorker(
      driverPort: self.driverPort,
      serverPort: self.serverPort
    )
    // credentialType: self.credentialType)
    qpsWorker.start {
      lifecycle.shutdown()
    }

    lifecycle.registerShutdown(label: "QPSWorker", .sync {
      try qpsWorker.syncShutdown()
    })

    lifecycle.start { error in
      // Start completion handler.
      // if a startup error occurred you can capture it here
      if let error = error {
        logger.error("failed starting \(self) ☠️: \(error)")
      } else {
        logger.info("\(self) started successfully 🚀")
      }
    }

    lifecycle.wait()

    logger.info("Worker has finished.")
  }
}

QPSWorkerApp.main()
