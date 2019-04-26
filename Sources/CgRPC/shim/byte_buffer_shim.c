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
#include "internal.h"
#include "cgrpc.h"

#include <stdbool.h>
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
