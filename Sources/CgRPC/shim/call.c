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

void cgrpc_call_destroy(cgrpc_call *call) {
  if (call->call) {
    grpc_call_unref(call->call);
  }
  free(call);
}

grpc_call_error cgrpc_call_perform(cgrpc_call *call, cgrpc_operations *operations, int64_t tag) {
  grpc_call_error error = grpc_call_start_batch(call->call,
                                                operations->ops,
                                                operations->ops_count,
                                                cgrpc_create_tag(tag),
                                                NULL);
  return error;
}

void cgrpc_call_cancel(cgrpc_call *call) {
  grpc_call_cancel(call->call, NULL);
}
