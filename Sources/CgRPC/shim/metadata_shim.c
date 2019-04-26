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

#include <grpc/support/alloc.h>

#include <stdlib.h>
#include <string.h>

#include "internal.h"
#include "cgrpc.h"

cgrpc_metadata_array *cgrpc_metadata_array_create() {
  cgrpc_metadata_array *metadata = (cgrpc_metadata_array *) gpr_malloc(sizeof(cgrpc_metadata_array));
  grpc_metadata_array_init(metadata);
  return metadata;
}

void cgrpc_metadata_array_unref_fields(cgrpc_metadata_array *array) {
  for (size_t i = 0; i < array->count; i++) {
    grpc_slice_unref(array->metadata[i].key);
    grpc_slice_unref(array->metadata[i].value);
  }
}

void cgrpc_metadata_array_destroy(cgrpc_metadata_array *array) {
  grpc_metadata_array_destroy(array);
  gpr_free(array);
}

size_t cgrpc_metadata_array_get_count(cgrpc_metadata_array *array) {
  return array->count;
}

char *cgrpc_metadata_array_copy_key_at_index(cgrpc_metadata_array *array, size_t index) {
  size_t length = GRPC_SLICE_LENGTH(array->metadata[index].key);
  char *str = (char *) malloc(length + 1);
  memcpy(str, GRPC_SLICE_START_PTR(array->metadata[index].key), length);
  str[length] = 0;
  return str;
}

char *cgrpc_metadata_array_copy_value_at_index(cgrpc_metadata_array *array, size_t index) {
  size_t length = GRPC_SLICE_LENGTH(array->metadata[index].value);
  char *str = (char *) malloc(length + 1);
  memcpy(str, GRPC_SLICE_START_PTR(array->metadata[index].value), length);
  str[length] = 0;
  return str;
}

cgrpc_byte_buffer *cgrpc_metadata_array_copy_data_value_at_index(cgrpc_metadata_array *array, size_t index) {
  size_t length = GRPC_SLICE_LENGTH(array->metadata[index].value);
  return cgrpc_byte_buffer_create_by_copying_data(GRPC_SLICE_START_PTR(array->metadata[index].value), length);
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

cgrpc_metadata_array *cgrpc_metadata_array_copy(cgrpc_metadata_array *src) {
  cgrpc_metadata_array *dst = cgrpc_metadata_array_create();
  if (src->count > 0) {
    dst->capacity = src->count;
    dst->metadata = gpr_malloc(dst->capacity * sizeof(grpc_metadata));
    dst->count = src->count;
    for (size_t i = 0; i < src->count; i++) {
      dst->metadata[i].key = grpc_slice_ref(src->metadata[i].key);
      dst->metadata[i].value = grpc_slice_ref(src->metadata[i].value);
      dst->metadata[i].flags = src->metadata[i].flags;
    }
  }
  return dst;
}

void cgrpc_metadata_array_append_metadata(cgrpc_metadata_array *metadata, const char *key, const char *value) {
  if (metadata->count >= metadata->capacity) {
    size_t new_capacity = 2 * metadata->capacity;
    if (new_capacity < 10) {
      new_capacity = 10;
    }
    
    if (metadata->metadata != NULL) {
      metadata->metadata = gpr_realloc(metadata->metadata, new_capacity * sizeof(grpc_metadata));
    } else {
      metadata->metadata = gpr_malloc(new_capacity * sizeof(grpc_metadata));
    }
    metadata->capacity = new_capacity;
  }

  size_t i = metadata->count;
  metadata->metadata[i].key = grpc_slice_from_copied_string(key);
  metadata->metadata[i].value = grpc_slice_from_copied_string(value);
  metadata->count++;
}
