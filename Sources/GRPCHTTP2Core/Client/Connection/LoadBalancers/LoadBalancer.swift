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

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
enum LoadBalancer: Sendable {
  case roundRobin(RoundRobinLoadBalancer)
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
extension LoadBalancer {
  init(_ loadBalancer: RoundRobinLoadBalancer) {
    self = .roundRobin(loadBalancer)
  }

  var id: LoadBalancerID {
    switch self {
    case .roundRobin(let loadBalancer):
      return loadBalancer.id
    }
  }

  var events: AsyncStream<LoadBalancerEvent> {
    switch self {
    case .roundRobin(let loadBalancer):
      return loadBalancer.events
    }
  }

  func run() async {
    switch self {
    case .roundRobin(let loadBalancer):
      await loadBalancer.run()
    }
  }

  func updateAddresses(_ endpoints: [Endpoint]) {
    switch self {
    case .roundRobin(let loadBalancer):
      loadBalancer.updateAddresses(endpoints)
    }
  }

  func close() {
    switch self {
    case .roundRobin(let loadBalancer):
      loadBalancer.close()
    }
  }

  func pickSubchannel() -> Subchannel? {
    switch self {
    case .roundRobin(let loadBalancer):
      return loadBalancer.pickSubchannel()
    }
  }
}
