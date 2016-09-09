/*
 *
 * Copyright 2016, Google Inc.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *
 *     * Redistributions of source code must retain the above copyright
 * notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above
 * copyright notice, this list of conditions and the following disclaimer
 * in the documentation and/or other materials provided with the
 * distribution.
 *     * Neither the name of Google Inc. nor the names of its
 * contributors may be used to endorse or promote products derived from
 * this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 */
#if SWIFT_PACKAGE
  import CgRPC
#endif

/// A general-purpose Mutex used to synchronize gRPC operations
/// but it can be used anywhere
public class Mutex {

  /// Pointer to underlying C representation
  private var mu: UnsafeMutableRawPointer!

  /// Initializes a Mutex
  public init() {
    mu = cgrpc_mutex_create();
  }

  deinit {
    cgrpc_mutex_destroy(mu);
  }

  /// Locks a Mutex
  ///
  /// Waits until no thread has a lock on the Mutex, 
  /// causes the calling thread to own an exclusive lock on the Mutex,
  /// then returns. 
  ///
  /// May block indefinitely or crash if the calling thread has a lock on the Mutex.
  public func lock() {
    cgrpc_mutex_lock(mu);
  }

  /// Unlocks a Mutex
  ///
  /// Releases an exclusive lock on the Mutex held by the calling thread.
  public func unlock() {
    cgrpc_mutex_unlock(mu);
  }
}
