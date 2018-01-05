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

cgrpc_channel *cgrpc_channel_create(const char *address) {
  cgrpc_channel *c = (cgrpc_channel *) malloc(sizeof (cgrpc_channel));
  // create the channel
  grpc_channel_args channel_args;
  channel_args.num_args = 0;
  c->channel = grpc_insecure_channel_create(address, &channel_args, NULL);
  c->completion_queue = grpc_completion_queue_create_for_next(NULL);
  return c;
}

cgrpc_channel *cgrpc_channel_create_secure(const char *address,
                                           const char *pem_root_certs,
                                           const char *host) {
  cgrpc_channel *c = (cgrpc_channel *) malloc(sizeof (cgrpc_channel));
  // create the channel

  int argMax = 2;
  grpc_channel_args *channelArgs = gpr_malloc(sizeof(grpc_channel_args));
  channelArgs->args = gpr_malloc(argMax * sizeof(grpc_arg));

  int argCount = 1;
  grpc_arg *arg = &channelArgs->args[0];
  arg->type = GRPC_ARG_STRING;
  arg->key = gpr_strdup("grpc.primary_user_agent");
  arg->value.string = gpr_strdup("grpc-swift/0.0.1");

  if (host) {
    argCount++;
    arg = &channelArgs->args[1];
    arg->type = GRPC_ARG_STRING;
    arg->key = gpr_strdup("grpc.ssl_target_name_override");
    arg->value.string = gpr_strdup(host);
  }

  channelArgs->num_args = argCount;

  grpc_channel_credentials *creds = grpc_ssl_credentials_create(pem_root_certs, NULL, NULL);
  c->channel = grpc_secure_channel_create(creds, address, channelArgs, NULL);
  c->completion_queue = grpc_completion_queue_create_for_next(NULL);
  return c;
}

cgrpc_channel *cgrpc_channel_create_securev2(const char *address,
                                             const char *pem_root_certs,
                                             const char *pem_private_key,
                                             const char *pem_cert_chain) {
  cgrpc_channel *c = (cgrpc_channel *) malloc(sizeof (cgrpc_channel));
  // create the channel
  int argMax = 2;
  grpc_channel_args *channelArgs = gpr_malloc(sizeof(grpc_channel_args));
  channelArgs->args = gpr_malloc(argMax * sizeof(grpc_arg));
    
  int argCount = 1;
  grpc_arg *arg = &channelArgs->args[0];
  arg->type = GRPC_ARG_STRING;
  arg->key = gpr_strdup("grpc.primary_user_agent");
  arg->value.string = gpr_strdup("grpc-swift/0.0.1");
    
  channelArgs->num_args = argCount;
  grpc_ssl_pem_key_cert_pair *pair = gpr_malloc(sizeof(grpc_ssl_pem_key_cert_pair));
  pair->cert_chain = gpr_strdup(pem_cert_chain);
  pair->private_key = gpr_strdup(pem_private_key);
  const char* root_certs = gpr_strdup(pem_root_certs);
  grpc_channel_credentials *creds = grpc_ssl_credentials_create(root_certs, pair, NULL);
  c->channel = grpc_secure_channel_create(creds, address, channelArgs, NULL);
  c->completion_queue = grpc_completion_queue_create_for_next(NULL);
  return c;
}

void cgrpc_channel_destroy(cgrpc_channel *c) {
  grpc_channel_destroy(c->channel);
  c->channel = NULL;

  grpc_completion_queue_shutdown(c->completion_queue);
  cgrpc_completion_queue_drain(c->completion_queue);
  grpc_completion_queue_destroy(c->completion_queue);
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
