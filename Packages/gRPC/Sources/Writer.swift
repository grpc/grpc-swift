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
import Foundation

enum WriterState {
  /**
   * The writer has not yet been given a writeable to which it can push its values. To have a writer
   * transition to the Started state, send it a startWithWriteable: message.
   *
   * A writer's state cannot be manually set to this value.
   */
  case NotStarted

  /** The writer might push values to the writeable at any moment. */
  case Started

  /**
   * The writer is temporarily paused, and won't send any more values to the writeable unless its
   * state is set back to Started. The writer might still transition to the Finished state at any
   * moment, and is allowed to send writesFinishedWithError: to its writeable.
   */
  case Paused

  /**
   * The writer has released its writeable and won't interact with it anymore.
   *
   * One seldomly wants to set a writer's state to this value, as its writeable isn't notified with
   * a writesFinishedWithError: message. Instead, sending finishWithError: to the writer will make
   * it notify the writeable and then transition to this state.
   */
  case Finished
}

// An object that can produce a sequence of values by calling a Writable
protocol Writer {
  var state: Int {get set}
  func start(with writable:Writable)
  func finish(with error:NSError)
}
