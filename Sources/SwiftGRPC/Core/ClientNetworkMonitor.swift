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
#if os(iOS)
import CoreTelephony
import Dispatch
import SystemConfiguration

/// This class may be used to monitor changes on the device that can cause gRPC to silently disconnect (making
/// it seem like active calls/connections are hanging), then manually shut down / restart gRPC channels as
/// needed. The root cause of these problems is that the backing gRPC-Core doesn't get the optimizations
/// made by iOS' networking stack when changes occur on the device such as switching from wifi to cellular,
/// switching between 3G and LTE, enabling/disabling airplane mode, etc.
/// Read more: https://github.com/grpc/grpc-swift/tree/master/README.md#known-issues
/// Original issue: https://github.com/grpc/grpc-swift/issues/337
open class ClientNetworkMonitor {
  private let queue: DispatchQueue
  private let callback: (State) -> Void
  private let reachability: SCNetworkReachability

  /// Instance of network info being used for obtaining cellular technology names.
  public let cellularInfo = CTTelephonyNetworkInfo()
  /// Whether the network is currently reachable. Backed by `SCNetworkReachability`.
  public private(set) var isReachable: Bool?
  /// Whether the device is currently using wifi (versus cellular).
  public private(set) var isUsingWifi: Bool?
  /// Name of the cellular technology being used (e.g., `CTRadioAccessTechnologyLTE`).
  public private(set) var cellularName: String?

  /// Represents a state of connectivity.
  public struct State: Equatable {
    /// The most recent change that was made to the state.
    public let lastChange: Change
    /// Whether this state is currently reachable/online.
    public let isReachable: Bool
  }

  /// A change in network condition.
  public enum Change: Equatable {
    /// Reachability changed (online <> offline).
    case reachability(isReachable: Bool)
    /// The device switched from cellular to wifi.
    case cellularToWifi
    /// The device switched from wifi to cellular.
    case wifiToCellular
    /// The cellular technology changed (e.g., 3G <> LTE).
    case cellularTechnology(technology: String)
  }

  /// Designated initializer for the network monitor. Initializer fails if reachability is unavailable.
  ///
  /// - Parameter host:     Host to use for monitoring reachability.
  /// - Parameter queue:    Queue on which to process and update network changes. Will create one if `nil`.
  ///                       Should always be used when accessing properties of this class.
  /// - Parameter callback: Closure to call whenever state changes.
  public init?(host: String = "google.com", queue: DispatchQueue? = nil, callback: @escaping (State) -> Void) {
    guard let reachability = SCNetworkReachabilityCreateWithName(nil, host) else {
      return nil
    }

    self.queue = queue ?? DispatchQueue(label: "SwiftGRPC.ClientNetworkMonitor.queue")
    self.callback = callback
    self.reachability = reachability
    self.startMonitoringReachability(reachability)
    self.startMonitoringCellular()
  }

  deinit {
    SCNetworkReachabilitySetCallback(self.reachability, nil, nil)
    SCNetworkReachabilityUnscheduleFromRunLoop(self.reachability, CFRunLoopGetMain(),
                                               CFRunLoopMode.commonModes.rawValue)
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: - Cellular

  private func startMonitoringCellular() {
    let notificationName: Notification.Name
    if #available(iOS 12.0, *) {
      notificationName = .CTServiceRadioAccessTechnologyDidChange
    } else {
      notificationName = .CTRadioAccessTechnologyDidChange
    }

    NotificationCenter.default.addObserver(self, selector: #selector(self.cellularDidChange(_:)),
                                           name: notificationName, object: nil)
  }

  @objc
  private func cellularDidChange(_ notification: NSNotification) {
    self.queue.async {
      let newCellularName: String?
      if #available(iOS 12.0, *) {
        let cellularKey = notification.object as? String
        newCellularName = cellularKey.flatMap { self.cellularInfo.serviceCurrentRadioAccessTechnology?[$0] }
      } else {
        newCellularName = notification.object as? String ?? self.cellularInfo.currentRadioAccessTechnology
      }

      if let newCellularName = newCellularName, self.cellularName != newCellularName {
        self.cellularName = newCellularName
        self.callback(State(lastChange: .cellularTechnology(technology: newCellularName),
                            isReachable: self.isReachable ?? false))
      }
    }
  }

  // MARK: - Reachability

  private func startMonitoringReachability(_ reachability: SCNetworkReachability) {
    let info = Unmanaged.passUnretained(self).toOpaque()
    var context = SCNetworkReachabilityContext(version: 0, info: info, retain: nil,
                                               release: nil, copyDescription: nil)
    let callback: SCNetworkReachabilityCallBack = { _, flags, info in
      let observer = info.map { Unmanaged<ClientNetworkMonitor>.fromOpaque($0).takeUnretainedValue() }
      observer?.reachabilityDidChange(with: flags)
    }

    SCNetworkReachabilitySetCallback(reachability, callback, &context)
    SCNetworkReachabilityScheduleWithRunLoop(reachability, CFRunLoopGetMain(),
                                             CFRunLoopMode.commonModes.rawValue)
    self.queue.async { [weak self] in
      var flags = SCNetworkReachabilityFlags()
      SCNetworkReachabilityGetFlags(reachability, &flags)
      self?.reachabilityDidChange(with: flags)
    }
  }

  private func reachabilityDidChange(with flags: SCNetworkReachabilityFlags) {
    self.queue.async {
      let isUsingWifi = !flags.contains(.isWWAN)
      let isReachable = flags.contains(.reachable)

      let notifyForWifi = self.isUsingWifi != nil && self.isUsingWifi != isUsingWifi
      let notifyForReachable = self.isReachable != nil && self.isReachable != isReachable

      self.isUsingWifi = isUsingWifi
      self.isReachable = isReachable

      if notifyForWifi {
        self.callback(State(lastChange: isUsingWifi ? .cellularToWifi : .wifiToCellular, isReachable: isReachable))
      }

      if notifyForReachable {
        self.callback(State(lastChange: .reachability(isReachable: isReachable), isReachable: isReachable))
      }
    }
  }
}
#endif
