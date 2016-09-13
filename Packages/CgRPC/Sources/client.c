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
#include <grpc/support/string_util.h>

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

cgrpc_client *cgrpc_client_create(const char *address) {
  cgrpc_client *c = (cgrpc_client *) malloc(sizeof (cgrpc_client));
  // create the client
  grpc_channel_args client_args;
  client_args.num_args = 0;
  c->client = grpc_insecure_channel_create(address, &client_args, NULL);
  c->completion_queue = grpc_completion_queue_create(NULL);
  return c;
}

cgrpc_client *cgrpc_client_create_secure(const char *address,
                                         const char *pem_root_certs,
                                         const char *host) {
  cgrpc_client *c = (cgrpc_client *) malloc(sizeof (cgrpc_client));
  // create the client

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
  c->client = grpc_secure_channel_create(creds, address, channelArgs, NULL);
  c->completion_queue = grpc_completion_queue_create(NULL);
  return c;
}


void cgrpc_client_destroy(cgrpc_client *c) {
  grpc_channel_destroy(c->client);
  c->client = NULL;

  grpc_completion_queue_shutdown(c->completion_queue);
  cgrpc_completion_queue_drain(c->completion_queue);
  grpc_completion_queue_destroy(c->completion_queue);
  free(c);
}

cgrpc_call *cgrpc_client_create_call(cgrpc_client *client,
                                           const char *method,
                                           const char *host,
                                           double timeout) {
  // create call
  gpr_timespec deadline = cgrpc_deadline_in_seconds_from_now(timeout);
  grpc_call *client_call = grpc_channel_create_call(client->client,
                                                    NULL,
                                                    GRPC_PROPAGATE_DEFAULTS,
                                                    client->completion_queue,
                                                    method,
                                                    host,
                                                    deadline,
                                                    NULL);
  cgrpc_call *call = (cgrpc_call *) malloc(sizeof(cgrpc_call));
  memset(call, 0, sizeof(cgrpc_call));
  call->call = client_call;
  return call;
}

cgrpc_completion_queue *cgrpc_client_completion_queue(cgrpc_client *client) {
  return client->completion_queue;
}
