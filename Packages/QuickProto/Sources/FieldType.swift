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
import Foundation

/// The "type" of a protocol buffer field
public enum FieldType: Int {
  case DOUBLE         = 1
  case FLOAT          = 2
  // Not ZigZag encoded.  Negative numbers take 10 bytes.  Use SINT64 if
  // negative values are likely.
  case INT64          = 3
  case UINT64         = 4
  // Not ZigZag encoded.  Negative numbers take 10 bytes.  Use SINT32 if
  // negative values are likely.
  case INT32          = 5
  case FIXED64        = 6
  case FIXED32        = 7
  case BOOL           = 8
  case STRING         = 9
  case GROUP          = 10  // Tag-delimited aggregate.
  case MESSAGE        = 11  // Length-delimited aggregate.
  // New in version 2.
  case BYTES          = 12
  case UINT32         = 13
  case ENUM           = 14
  case SFIXED32       = 15
  case SFIXED64       = 16
  case SINT32         = 17  // Uses ZigZag encoding.
  case SINT64         = 18
}
