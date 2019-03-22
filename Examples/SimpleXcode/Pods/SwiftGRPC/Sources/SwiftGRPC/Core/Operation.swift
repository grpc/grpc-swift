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

enum Operation {
  case sendInitialMetadata(Metadata)
  case sendMessage(ByteBuffer)
  case sendCloseFromClient
  case sendStatusFromServer(StatusCode, String, Metadata)
  case receiveInitialMetadata
  case receiveMessage
  case receiveStatusOnClient
  case receiveCloseOnServer
}
