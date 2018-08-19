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

#include <stdio.h>

grpc_completion_queue *cgrpc_completion_queue_create_for_next(void) {
  return grpc_completion_queue_create_for_next(NULL);
}

grpc_event cgrpc_completion_queue_get_next_event(grpc_completion_queue *cq, double timeout) {
  gpr_timespec deadline = cgrpc_deadline_in_seconds_from_now(timeout);
  if (timeout < 0) {
    deadline = gpr_inf_future(GPR_CLOCK_REALTIME);
  }
  return grpc_completion_queue_next(cq, deadline, NULL);
}

void cgrpc_completion_queue_drain(grpc_completion_queue *cq) {
  grpc_event ev;
  do {
    ev = grpc_completion_queue_next(cq, cgrpc_deadline_in_seconds_from_now(5), NULL);
  } while (ev.type != GRPC_QUEUE_SHUTDOWN);
}

void cgrpc_completion_queue_shutdown(cgrpc_completion_queue *cq) {
  grpc_completion_queue_shutdown(cq);
}

