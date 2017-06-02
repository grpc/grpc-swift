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
