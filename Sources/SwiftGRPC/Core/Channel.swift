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
  import Dispatch
#endif
import Foundation

/// A gRPC Channel
public class Channel {
  /// Pointer to underlying C representation
  private let underlyingChannel: UnsafeMutableRawPointer

  /// Completion queue for channel call operations
  private let completionQueue: CompletionQueue

  /// Timeout for new calls
  public var timeout: TimeInterval = 600.0

  /// Default host to use for new calls
  public var host: String

  /// Connectivity state observers
  private var connectivityObservers: [ConnectivityObserver] = []

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

  deinit {
    connectivityObservers.forEach { $0.shutdown() }
    cgrpc_channel_destroy(underlyingChannel)
    completionQueue.shutdown()
  }

  /// Constructs a Call object to make a gRPC API call
  ///
  /// - Parameter method: the gRPC method name for the call
  /// - Parameter host: the gRPC host name for the call. If unspecified, defaults to the Client host
  /// - Parameter timeout: a timeout value in seconds
  /// - Returns: a Call object that can be used to perform the request
  public func makeCall(_ method: String, host: String = "", timeout: TimeInterval? = nil) -> Call {
    let host = (host == "") ? self.host : host
    let timeout = timeout ?? self.timeout
    let underlyingCall = cgrpc_channel_create_call(underlyingChannel, method, host, timeout)!
    return Call(underlyingCall: underlyingCall, owned: true, completionQueue: completionQueue)
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
  public func subscribe(callback: @escaping (ConnectivityState) -> Void) {
    connectivityObservers.append(ConnectivityObserver(underlyingChannel: underlyingChannel, currentState: connectivityState(), callback: callback))
  }
}

private extension Channel {
  class ConnectivityObserver {
    private let completionQueue: CompletionQueue
    private let underlyingChannel: UnsafeMutableRawPointer
    private let underlyingCompletionQueue: UnsafeMutableRawPointer
    private let callback: (ConnectivityState) -> Void
    private var lastState: ConnectivityState
    private var hasBeenShutdown = false
    private let stateMutex: Mutex = Mutex()

    init(underlyingChannel: UnsafeMutableRawPointer, currentState: ConnectivityState, callback: @escaping (ConnectivityState) -> ()) {
      self.underlyingChannel = underlyingChannel
      self.underlyingCompletionQueue = cgrpc_completion_queue_create_for_next()
      self.completionQueue = CompletionQueue(underlyingCompletionQueue: self.underlyingCompletionQueue, name: "Connectivity State")
      self.callback = callback
      self.lastState = currentState
      run()
    }

    deinit {
      shutdown()
    }

    private func run() {
      let spinloopThreadQueue = DispatchQueue(label: "SwiftGRPC.ConnectivityObserver.run.spinloopThread")

      spinloopThreadQueue.async {
        while true  {
          guard (self.stateMutex.synchronize{ !self.hasBeenShutdown }) else {
            return
          }
            
          guard let underlyingState = self.lastState.underlyingState else { return }

          let deadline: TimeInterval = 0.2
          cgrpc_channel_watch_connectivity_state(self.underlyingChannel, self.underlyingCompletionQueue, underlyingState, deadline, nil)
          let event = self.completionQueue.wait(timeout: deadline)
          
          guard (self.stateMutex.synchronize{ !self.hasBeenShutdown }) else {
            return
          }

          switch event.type {
          case .complete:
            let newState = ConnectivityState(cgrpc_channel_check_connectivity_state(self.underlyingChannel, 0))

            if newState != self.lastState {
              self.callback(newState)
            }
            self.lastState = newState

          case .queueShutdown:
            return

          default:
            continue
          }
        }
      }
    }

    func shutdown() {
      stateMutex.synchronize {
        hasBeenShutdown = true
      }
      completionQueue.shutdown()
    }
  }
}
