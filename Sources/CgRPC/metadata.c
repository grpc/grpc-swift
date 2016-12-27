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
#include "internal.h"
#include "cgrpc.h"

#include "stdlib.h"
#include "string.h"

cgrpc_metadata_array *cgrpc_metadata_array_create() {
  cgrpc_metadata_array *metadata = (cgrpc_metadata_array *) malloc(sizeof(cgrpc_metadata_array));
  memset(metadata, 0, sizeof(cgrpc_metadata_array));
  return metadata;
}

void cgrpc_metadata_array_destroy(cgrpc_metadata_array *array) {
  grpc_metadata_array_destroy(array);
}

size_t cgrpc_metadata_array_get_count(cgrpc_metadata_array *array) {
  return array->count;
}

const char *cgrpc_metadata_array_get_key_at_index(cgrpc_metadata_array *array, size_t index) {
  return array->metadata[index].key;
}

const char *cgrpc_metadata_array_get_value_at_index(cgrpc_metadata_array *array, size_t index) {
  return array->metadata[index].value;
}

void cgrpc_metadata_array_move_metadata(cgrpc_metadata_array *destination,
                                       cgrpc_metadata_array *source) {
  destination->count = source->count;
  destination->capacity = source->capacity;
  destination->metadata = source->metadata;

  source->count = 0;
  source->capacity = 0;
  source->metadata = NULL;
}

void cgrpc_metadata_array_append_metadata(cgrpc_metadata_array *metadata, const char *key, const char *value) {
  if (!metadata->count) {
    metadata->metadata = (grpc_metadata *) malloc(10 * sizeof(grpc_metadata));
    metadata->count = 0;
    metadata->capacity = 10;
  }
  if (metadata->count < metadata->capacity) {
    size_t i = metadata->count;
    metadata->metadata[i].key = strdup(key);
    metadata->metadata[i].value = strdup(value);
    metadata->metadata[i].value_length = strlen(value);
    metadata->count++;
  }
}
