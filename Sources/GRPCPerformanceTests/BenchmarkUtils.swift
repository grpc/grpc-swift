/*
 * Copyright 2021, gRPC Authors All rights reserved.
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
import Dispatch

/// The results of a benchmark.
struct BenchmarkResults {
  /// The description of the benchmark.
  var desc: String

  /// The duration of each run of the benchmark in milliseconds.
  var milliseconds: [UInt64]
}

extension BenchmarkResults: CustomStringConvertible {
  var description: String {
    return "\(self.desc): \(self.milliseconds.map(String.init).joined(separator: ","))"
  }
}

/// Runs the benchmark and prints the duration in milliseconds for each run.
///
/// - Parameters:
///   - description: A description of the benchmark.
///   - benchmark: The benchmark which should be run.
///   - spec: The specification for the test run.
func measureAndPrint(description: String, benchmark: Benchmark, spec: TestSpec) {
  switch spec.action {
  case .list:
    print(description)
  case let .run(filter):
    guard filter.shouldRun(description) else {
      return
    }
    #if CACHEGRIND
    _ = measure(description, benchmark: benchmark, repeats: 1)
    #else
    print(measure(description, benchmark: benchmark, repeats: spec.repeats))
    #endif
  }
}

/// Runs the given benchmark multiple times, recording the wall time for each iteration.
///
/// - Parameters:
///   - description: A description of the benchmark.
///   - benchmark: The benchmark to run.
///   - repeats: the number of times to run the benchmark.
func measure(_ description: String, benchmark: Benchmark, repeats: Int) -> BenchmarkResults {
  var milliseconds: [UInt64] = []
  for _ in 0 ..< repeats {
    do {
      try benchmark.setUp()

      #if !CACHEGRIND
      let start = DispatchTime.now().uptimeNanoseconds
      #endif
      _ = try benchmark.run()

      #if !CACHEGRIND
      let end = DispatchTime.now().uptimeNanoseconds

      milliseconds.append((end - start) / 1_000_000)
      #endif
    } catch {
      // If tearDown fails now then there's not a lot we can do!
      try? benchmark.tearDown()
      return BenchmarkResults(desc: description, milliseconds: [])
    }

    do {
      try benchmark.tearDown()
    } catch {
      return BenchmarkResults(desc: description, milliseconds: [])
    }
  }

  return BenchmarkResults(desc: description, milliseconds: milliseconds)
}
