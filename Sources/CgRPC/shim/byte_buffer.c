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
#include <stdio.h>

#include "internal.h"
#include "cgrpc.h"

#include <stdio.h>
#include <assert.h>
#include <string.h>

void cgrpc_byte_buffer_destroy(cgrpc_byte_buffer *bb) {
  grpc_byte_buffer_destroy(bb);
}

cgrpc_byte_buffer *cgrpc_byte_buffer_create_by_copying_data(const void *source, size_t len) {
  grpc_slice request_payload_slice = grpc_slice_from_copied_buffer(source, len);
  cgrpc_byte_buffer *bb = grpc_raw_byte_buffer_create(&request_payload_slice, 1);
  grpc_slice_unref(request_payload_slice);
  return bb;
}

const void *cgrpc_byte_buffer_copy_data(cgrpc_byte_buffer *bb, size_t *length) {
  if (!bb) {
    return NULL;
  }
  grpc_byte_buffer_reader reader;
  bool success = grpc_byte_buffer_reader_init(&reader, bb);
  if (!success) {
    return NULL;
  }
  grpc_slice slice = grpc_byte_buffer_reader_readall(&reader);
  *length = (size_t) GRPC_SLICE_LENGTH(slice);
  void *result = malloc(*length);
  memcpy(result, GRPC_SLICE_START_PTR(slice), *length);
  grpc_slice_unref(slice);
  grpc_byte_buffer_reader_destroy(&reader);
  return result;
}
