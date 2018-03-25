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
  /// Pointer to underlying C representation
  private let underlyingChannel: UnsafeMutableRawPointer

  /// Completion queue for channel call operations
  private let completionQueue: CompletionQueue

  /// Timeout for new calls
  public var timeout: TimeInterval = 600.0

  /// Default host to use for new calls
  public var host: String

  /// Connectivity state observers
  private var observers: [ConnectivityObserver] = []

  /// Initializes a gRPC channel
  ///
  /// - Parameter address: the address of the server to be called
  /// - Parameter secure: if true, use TLS
  public init(address: String, secure: Bool = true) {
    host = address
    if secure {
      underlyingChannel = cgrpc_channel_create_secure(address, roots_pem(), nil)
    } else {
      underlyingChannel = cgrpc_channel_create(address)
    }
    completionQueue = CompletionQueue(
      underlyingCompletionQueue: cgrpc_channel_completion_queue(underlyingChannel), name: "Client")
    completionQueue.run() // start a loop that watches the channel's completion queue
  }

  /// Initializes a gRPC channel
  ///
  /// - Parameter address: the address of the server to be called
  /// - Parameter certificates: a PEM representation of certificates to use
  /// - Parameter host: an optional hostname override
  public init(address: String, certificates: String, host: String?) {
    self.host = address
    underlyingChannel = cgrpc_channel_create_secure(address, certificates, host)
    completionQueue = CompletionQueue(
      underlyingCompletionQueue: cgrpc_channel_completion_queue(underlyingChannel), name: "Client")
    completionQueue.run() // start a loop that watches the channel's completion queue
  }

  deinit {
    cgrpc_channel_destroy(underlyingChannel)
    completionQueue.shutdown()
  }

  /// Constructs a Call object to make a gRPC API call
  ///
  /// - Parameter method: the gRPC method name for the call
  /// - Parameter host: the gRPC host name for the call. If unspecified, defaults to the Client host
  /// - Parameter timeout: a timeout value in seconds
  /// - Returns: a Call object that can be used to perform the request
  public func makeCall(_ method: String, host: String = "") -> Call {
    let host = (host == "") ? self.host : host
    let underlyingCall = cgrpc_channel_create_call(underlyingChannel, method, host, timeout)!
    return Call(underlyingCall: underlyingCall, owned: true, completionQueue: completionQueue)
  }

  public func connectivityState(tryToConnect: Bool = false) -> ConnectivityState {
    return ConnectivityState.connectivityState(cgrpc_channel_check_connectivity_state(underlyingChannel, tryToConnect ? 1 : 0))
  }

  public func subscribe(sourceState: ConnectivityState, tryToConnect: Bool = false, callback: @escaping (ConnectivityState) -> ()) {
    var observer = observers.first(where: { $0.state == sourceState })

    if observer == nil {
      let newObserver = ConnectivityObserver(state: sourceState, underlyingChannel: underlyingChannel, tryToConnect: tryToConnect)
      observers.append(newObserver)
      observer = newObserver
    }

    observer?.callbacks.append(callback)
    observer?.polling = true
  }
}

private extension Channel {
  class ConnectivityObserver: Equatable {
    let state: ConnectivityState
    let queue: CompletionQueue
    let underlyingChannel: UnsafeMutableRawPointer
    let underlyingCompletionQueue: UnsafeMutableRawPointer
    private(set) var tryToConnect: Bool
    var callbacks: [(ConnectivityState) -> ()] = []
    private var lastState: ConnectivityState

    var polling: Bool = false {
      didSet {
        if polling == true && oldValue == false {
          run()
        }
      }
    }

    init(state: ConnectivityState, underlyingChannel: UnsafeMutableRawPointer, tryToConnect: Bool) {
      self.state = state
      self.underlyingChannel = underlyingChannel
      self.tryToConnect = tryToConnect
      self.underlyingCompletionQueue = cgrpc_completion_queue_create_for_next()
      self.queue = CompletionQueue(underlyingCompletionQueue: self.underlyingCompletionQueue, name: "Connectivity State")
      self.lastState = ConnectivityState.connectivityState(cgrpc_channel_check_connectivity_state(self.underlyingChannel, 0))
    }

    deinit {
      queue.shutdown()
    }

    private func run() {
      DispatchQueue.global().async { [weak self] in
        guard let `self` = self, let underlyingState = self.lastState.underlyingState else { return }

        while self.polling {
          guard !self.callbacks.isEmpty && !self.tryToConnect else {
            self.polling = false
            break
          }

          defer { self.tryToConnect = false }

          let deadline: TimeInterval = 0.2
          cgrpc_channel_watch_connectivity_state(self.underlyingChannel, self.underlyingCompletionQueue, underlyingState, deadline, nil)
          let event = self.queue.wait(timeout: deadline)

          if event.success == 1 || self.tryToConnect {
            let newState = ConnectivityState.connectivityState(cgrpc_channel_check_connectivity_state(self.underlyingChannel, self.tryToConnect ? 1 : 0))

            guard newState != self.lastState else { continue }
            defer { self.lastState = newState }

            if self.lastState == self.state {
              self.callbacks.forEach({ $0(newState) })
            }
          }
        }
      }
    }

    static func == (lhs: ConnectivityObserver, rhs: ConnectivityObserver) -> Bool {
      return lhs.state == rhs.state
    }
  }
}

extension Channel {
  public enum ConnectivityState {
    /// Channel has just been initialized
    case initialized
    /// Channel is idle
    case idle
    /// Channel is connecting
    case connecting
    /// Channel is ready for work
    case ready
    /// Channel has seen a failure but expects to recover
    case transientFailure
    /// Channel has seen a failure that it cannot recover from
    case shutdown
    /// Channel connectivity state is unknown
    case unknown

    fileprivate static func connectivityState(_ value: grpc_connectivity_state) -> ConnectivityState {
      switch value {
      case GRPC_CHANNEL_INIT:
        return .initialized
      case GRPC_CHANNEL_IDLE:
        return .idle
      case GRPC_CHANNEL_CONNECTING:
        return .connecting
      case GRPC_CHANNEL_READY:
        return .ready
      case GRPC_CHANNEL_TRANSIENT_FAILURE:
        return .transientFailure
      case GRPC_CHANNEL_SHUTDOWN:
        return .shutdown
      default:
        return .unknown
      }
    }

    fileprivate var underlyingState: grpc_connectivity_state? {
      switch self {
      case .initialized:
        return GRPC_CHANNEL_INIT
      case .idle:
        return GRPC_CHANNEL_IDLE
      case .connecting:
        return GRPC_CHANNEL_CONNECTING
      case .ready:
        return GRPC_CHANNEL_READY
      case .transientFailure:
        return GRPC_CHANNEL_TRANSIENT_FAILURE
      case .shutdown:
        return GRPC_CHANNEL_SHUTDOWN
      default:
        return nil
      }
    }
  }
}
