/*
 * Copyright 2023, gRPC Authors All rights reserved.
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
import Benchmark
import GRPCCore

let benchmarks = {
  Benchmark.defaultConfiguration = .init(
    metrics: [
      .mallocCountTotal,
      .syscalls,
      .readSyscalls,
      .writeSyscalls,
      .memoryLeaked,
      .retainCount,
      .releaseCount,
    ]
  )

  // async code is currently still quite flaky in the number of retain/release it does so we don't measure them today
  var config = Benchmark.defaultConfiguration
  config.metrics.removeAll(where: { $0 == .retainCount || $0 == .releaseCount })
  // Let p90 be off by 50. Benchmarks should do 1000s of iterations so this is small enough.
  config.thresholds = [.mallocCountTotal: BenchmarkThresholds(absolute: [.p90: 50])]

  Benchmark("Metadata_Add_string", configuration: config) { benchmark in
    for _ in benchmark.scaledIterations {
      var metadata = Metadata()
      for i in 0 ..< 1000 {
        metadata.addString("\(i)", forKey: "\(i)")
      }
    }
  }

  Benchmark("Metadata_Add_binary", configuration: config) { benchmark in
    let value: [UInt8] = [1, 2, 3]
    for _ in benchmark.scaledIterations {
      var metadata = Metadata()

      benchmark.startMeasurement()
      for i in 0 ..< 1000 {
        metadata.addBinary(value, forKey: "\(i)")
      }
      benchmark.stopMeasurement()
    }
  }

  Benchmark("Metadata_Remove_values_for_key", configuration: config) { benchmark in
    for _ in benchmark.scaledIterations {
      var metadata = Metadata()
      for i in 0 ..< 1000 {
        metadata.addString("value", forKey: "\(i)")
      }

      benchmark.startMeasurement()
      for i in 0 ..< 1000 {
        metadata.removeAllValues(forKey: "\(i)")
      }
      benchmark.stopMeasurement()
    }
  }

  Benchmark("Metadata_Iterate_all_values", configuration: config) { benchmark in
    for _ in benchmark.scaledIterations {
      var metadata = Metadata()
      for i in 0 ..< 1000 {
        metadata.addString("value", forKey: "key")
      }

      benchmark.startMeasurement()
      for value in metadata["key"] {
        blackHole(value)
      }
      benchmark.stopMeasurement()
    }
  }

  Benchmark("Metadata_Iterate_string_values", configuration: config) { benchmark in
    for _ in benchmark.scaledIterations {
      var metadata = Metadata()
      for i in 0 ..< 1000 {
        metadata.addString("\(i)", forKey: "key")
      }

      benchmark.startMeasurement()
      for value in metadata[stringValues: "key"] {
        blackHole(value)
      }
      benchmark.stopMeasurement()
    }
  }

  Benchmark(
    "Metadata_Iterate_binary_values_when_only_binary_values_stored",
    configuration: config
  ) { benchmark in
    for _ in benchmark.scaledIterations {
      var metadata = Metadata()
      for i in 0 ..< 1000 {
        metadata.addBinary([1], forKey: "key")
      }

      benchmark.startMeasurement()
      for value in metadata[binaryValues: "key"] {
        blackHole(value)
      }
      benchmark.stopMeasurement()
    }
  }

  Benchmark(
    "Metadata_Iterate_binary_values_when_only_strings_stored",
    configuration: config
  ) { benchmark in
    for _ in benchmark.scaledIterations {
      var metadata = Metadata()
      for i in 0 ..< 1000 {
        metadata.addString("\(i)", forKey: "key")
      }

      benchmark.startMeasurement()
      for value in metadata[binaryValues: "key"] {
        blackHole(value)
      }
      benchmark.stopMeasurement()
    }
  }
}
