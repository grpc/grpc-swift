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
#if compiler(>=5.5) && canImport(_Concurrency)

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension Call {
  internal func makeRequestStreamWriter() -> GRPCAsyncRequestStreamWriter<Request> {
    let delegate = GRPCAsyncRequestStreamWriter<Request>.Delegate(
      compressionEnabled: self.options.messageEncoding.enabledForRequests
    ) { request, metadata in
      self.send(.message(request, metadata), promise: nil)
    } finish: {
      self.send(.end, promise: nil)
    }

    return GRPCAsyncRequestStreamWriter(asyncWriter: .init(delegate: delegate))
  }
}

#endif // compiler(>=5.5) && canImport(_Concurrency)
