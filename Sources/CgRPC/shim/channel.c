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
#include <grpc/support/string_util.h>
#include <grpc/support/alloc.h>

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

cgrpc_channel *cgrpc_channel_create(const char *address,
                                    grpc_arg *args,
                                    int number_args) {
  cgrpc_channel *c = (cgrpc_channel *) malloc(sizeof (cgrpc_channel));

  grpc_channel_args *channel_args = gpr_malloc(sizeof(grpc_channel_args));
  channel_args->args = args;
  channel_args->num_args = number_args;

  // create the channel
  c->channel = grpc_insecure_channel_create(address, channel_args, NULL);
  c->completion_queue = grpc_completion_queue_create_for_next(NULL);
  return c;
}

cgrpc_channel *cgrpc_channel_create_secure(const char *address,
                                           const char *pem_root_certs,
                                           grpc_arg *args,
                                           int number_args) {
  cgrpc_channel *c = (cgrpc_channel *) malloc(sizeof (cgrpc_channel));
  // create the channel

  grpc_channel_args *channel_args = gpr_malloc(sizeof(grpc_channel_args));
  channel_args->args = args;
  channel_args->num_args = number_args;

  grpc_channel_credentials *creds = grpc_ssl_credentials_create(pem_root_certs, NULL, NULL);
  c->channel = grpc_secure_channel_create(creds, address, channel_args, NULL);
  c->completion_queue = grpc_completion_queue_create_for_next(NULL);
  return c;
}


void cgrpc_channel_destroy(cgrpc_channel *c) {
  grpc_channel_destroy(c->channel);
  c->channel = NULL;
  free(c);
}

grpc_slice host_slice;

cgrpc_call *cgrpc_channel_create_call(cgrpc_channel *channel,
                                      const char *method,
                                      const char *host,
                                      double timeout) {
  // create call
  host_slice = grpc_slice_from_copied_string(host);
  gpr_timespec deadline = cgrpc_deadline_in_seconds_from_now(timeout);
  // The resulting call will have a retain call of +1. We'll release it in `cgrpc_call_destroy()`.
  grpc_call *channel_call = grpc_channel_create_call(channel->channel,
                                                     NULL,
                                                     GRPC_PROPAGATE_DEFAULTS,
                                                     channel->completion_queue,
                                                     grpc_slice_from_copied_string(method),
                                                     &host_slice,
                                                     deadline,
                                                     NULL);
  cgrpc_call *call = (cgrpc_call *) malloc(sizeof(cgrpc_call));
  memset(call, 0, sizeof(cgrpc_call));
  call->call = channel_call;
  return call;
}

cgrpc_completion_queue *cgrpc_channel_completion_queue(cgrpc_channel *channel) {
  return channel->completion_queue;
}

grpc_connectivity_state cgrpc_channel_check_connectivity_state(cgrpc_channel *channel, int try_to_connect) {
  return grpc_channel_check_connectivity_state(channel->channel, try_to_connect);
}
