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

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
extension Result where Failure == any Error {
  /// Like `Result(catching:)`, but `async`.
  ///
  /// - Parameter body: An `async` closure to catch the result of.
  @inlinable
  init(catching body: () async throws -> Success) async {
    do {
      self = .success(try await body())
    } catch {
      self = .failure(error)
    }
  }

  /// Attempts to map the error to the given error type.
  ///
  /// If the cast fails then the provided closure is used to create an error of the given type.
  ///
  /// - Parameters:
  ///   - errorType: The type of error to cast to.
  ///   - buildError: A closure which constructs the desired error if the cast fails.
  @inlinable
  func castError<NewError: Error>(
    to errorType: NewError.Type = NewError.self,
    or buildError: (any Error) -> NewError
  ) -> Result<Success, NewError> {
    return self.mapError { error in
      return (error as? NewError) ?? buildError(error)
    }
  }
}
