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
import NIOSSL

// This file contains shims to notify users of API changes between v1.0.0-alpha.1 and v1.0.0.

// TODO: Remove these shims before v1.0.0 is tagged.

extension ClientConnection.Configuration {
  @available(*, deprecated, message: "use 'tls' and 'ClientConnection.Configuration.TLS'")
  public var tlsConfiguration: TLSConfiguration? {
    return nil
  }
}

extension Server.Configuration {
  @available(*, deprecated, message: "use 'tls' and 'Server.Configuration.TLS'")
  public var tlsConfiguration: TLSConfiguration? {
    return nil
  }
}

@available(*, deprecated, renamed: "PlatformSupport")
public enum GRPCNIO {}
