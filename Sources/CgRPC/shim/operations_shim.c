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

#include <stdlib.h>
#include <string.h>
#include <assert.h>

cgrpc_operations *cgrpc_operations_create() {
  return (cgrpc_operations *) malloc(sizeof (cgrpc_operations));
}

void cgrpc_operations_destroy(cgrpc_operations *operations) {
  free(operations->ops);
  free(operations);
}

void cgrpc_operations_reserve_space_for_operations(cgrpc_operations *operations, int max_operations) {
  operations->ops = (grpc_op *) malloc(max_operations * sizeof(grpc_op));
  memset(operations->ops, 0, max_operations * sizeof(grpc_op));
  operations->ops_count = 0;
}

void cgrpc_operations_add_operation(cgrpc_operations *operations, cgrpc_observer *observer) {
  grpc_op *op = &(operations->ops[operations->ops_count]);
  cgrpc_observer_apply(observer, op);
  operations->ops_count++;
}
