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
#if SWIFT_PACKAGE
import CgRPC
#endif
import Foundation

/// A gRPC Channel
public class Channel {
  private let mutex = Mutex()
  /// Weak references to API calls using this channel that are in-flight
  private let activeCalls = NSHashTable<Call>.weakObjects()
  /// Pointer to underlying C representation
  private let underlyingChannel: UnsafeMutableRawPointer
  /// Completion queue for channel call operations
  private let completionQueue: CompletionQueue
  /// Observer for connectivity state changes. Created lazily if needed
  private var connectivityObserver: ConnectivityObserver?
  /// Whether the gRPC channel has been shut down
  private var hasBeenShutdown = false

  /// Timeout for new calls
  public var timeout: TimeInterval = 600.0

  /// Default host to use for new calls
  public var host: String

  /// Errors that may be thrown by the channel
  enum Error: Swift.Error {
    /// Action cannot be performed because the channel has already been shut down
    case alreadyShutdown
    /// Failed to create a new call within the gRPC stack
    case callCreationFailed
  }

  /// Initializes a gRPC channel
  ///
  /// - Parameter address: the address of the server to be called
  /// - Parameter secure: if true, use TLS
  /// - Parameter arguments: list of channel configuration options
  public init(address: String, secure: Bool = true, arguments: [Argument] = []) {
    gRPC.initialize()
    host = address
    let argumentWrappers = arguments.map { $0.toCArg() }

    underlyingChannel = withExtendedLifetime(argumentWrappers) {
      var argumentValues = argumentWrappers.map { $0.wrapped }
      if secure {
        return cgrpc_channel_create_secure(address, kRootCertificates, nil, nil, &argumentValues, Int32(arguments.count))
      } else {
        return cgrpc_channel_create(address, &argumentValues, Int32(arguments.count))
      }
    }
    completionQueue = CompletionQueue(underlyingCompletionQueue: cgrpc_channel_completion_queue(underlyingChannel), name: "Client")
    completionQueue.run() // start a loop that watches the channel's completion queue
  }

  /// Initializes a gRPC channel
  ///
  /// - Parameter address: the address of the server to be called
  /// - Parameter arguments: list of channel configuration options
  public init(googleAddress: String, arguments: [Argument] = []) {
    gRPC.initialize()
    host = googleAddress
    let argumentWrappers = arguments.map { $0.toCArg() }

    underlyingChannel = withExtendedLifetime(argumentWrappers) {
      var argumentValues = argumentWrappers.map { $0.wrapped }
      return cgrpc_channel_create_google(googleAddress, &argumentValues, Int32(arguments.count))
    }

    completionQueue = CompletionQueue(underlyingCompletionQueue: cgrpc_channel_completion_queue(underlyingChannel), name: "Client")
    completionQueue.run() // start a loop that watches the channel's completion queue
  }

  /// Initializes a gRPC channel
  ///
  /// - Parameter address: the address of the server to be called
  /// - Parameter certificates: a PEM representation of certificates to use.
  /// - Parameter clientCertificates: a PEM representation of the client certificates to use
  /// - Parameter clientKey: a PEM representation of the client key to use
  /// - Parameter arguments: list of channel configuration options
  public init(address: String, certificates: String = kRootCertificates, clientCertificates: String? = nil, clientKey: String? = nil, arguments: [Argument] = []) {
    gRPC.initialize()
    host = address
    let argumentWrappers = arguments.map { $0.toCArg() }

    underlyingChannel = withExtendedLifetime(argumentWrappers) {
      var argumentValues = argumentWrappers.map { $0.wrapped }
      return cgrpc_channel_create_secure(address, certificates, clientCertificates, clientKey, &argumentValues, Int32(arguments.count))
    }
    completionQueue = CompletionQueue(underlyingCompletionQueue: cgrpc_channel_completion_queue(underlyingChannel), name: "Client")
    completionQueue.run() // start a loop that watches the channel's completion queue
  }

  /// Shut down the channel. No new calls may be made using this channel after it is shut down. Any in-flight calls using this channel will be canceled
  public func shutdown() {
    self.mutex.synchronize {
      guard !self.hasBeenShutdown else { return }

      self.hasBeenShutdown = true
      self.connectivityObserver?.shutdown()
      cgrpc_channel_destroy(self.underlyingChannel)
      self.completionQueue.shutdown()
      self.activeCalls.allObjects.forEach { $0.cancel() }
    }
  }

  deinit {
    self.shutdown()
  }

  /// Constructs a Call object to make a gRPC API call
  ///
  /// - Parameter method: the gRPC method name for the call
  /// - Parameter host: the gRPC host name for the call. If unspecified, defaults to the Client host
  /// - Parameter timeout: a timeout value in seconds
  /// - Returns: a Call object that can be used to perform the request
  public func makeCall(_ method: String, host: String? = nil, timeout: TimeInterval? = nil) throws -> Call {
    guard (self.mutex.synchronize { !self.hasBeenShutdown }) else {
      throw Error.alreadyShutdown
    }

    guard let underlyingCall = cgrpc_channel_create_call(
      self.underlyingChannel, method, host ?? self.host, timeout ?? self.timeout) else
    {
      throw Error.callCreationFailed
    }

    let call = Call(underlyingCall: underlyingCall, owned: true, completionQueue: self.completionQueue)
    self.mutex.synchronize { self.activeCalls.add(call) }
    return call
  }

  /// Check the current connectivity state
  ///
  /// - Parameter tryToConnect: boolean value to indicate if should try to connect if channel's connectivity state is idle
  /// - Returns: a ConnectivityState value representing the current connectivity state of the channel
  public func connectivityState(tryToConnect: Bool = false) -> ConnectivityState {
    return ConnectivityState(cgrpc_channel_check_connectivity_state(underlyingChannel, tryToConnect ? 1 : 0))
  }

  /// Subscribe to connectivity state changes
  ///
  /// - Parameter callback: block executed every time a new connectivity state is detected
  public func addConnectivityObserver(callback: @escaping (ConnectivityState) -> Void) {
    self.mutex.synchronize {
      let observer: ConnectivityObserver
      if let existingObserver = self.connectivityObserver {
        observer = existingObserver
      } else {
        observer = ConnectivityObserver(underlyingChannel: self.underlyingChannel)
        self.connectivityObserver = observer
      }

      observer.addConnectivityObserver(callback: callback)
    }
  }
}
