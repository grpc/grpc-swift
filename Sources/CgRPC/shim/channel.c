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

#include <stdlib.h>

cgrpc_channel *cgrpc_channel_create(const char *address,
                                    grpc_arg *args,
                                    int num_args) {
  cgrpc_channel *c = (cgrpc_channel *) gpr_zalloc(sizeof (cgrpc_channel));

  grpc_channel_args channel_args;
  channel_args.args = args;
  channel_args.num_args = num_args;

  c->channel = grpc_insecure_channel_create(address, &channel_args, NULL);
  c->completion_queue = grpc_completion_queue_create_for_next(NULL);
  return c;
}

cgrpc_channel *cgrpc_channel_create_secure(const char *address,
                                           const char *pem_root_certs,
                                           const char *client_certs,
                                           const char *client_private_key,
                                           grpc_arg *args,
                                           int num_args) {
  cgrpc_channel *c = (cgrpc_channel *) gpr_zalloc(sizeof (cgrpc_channel));

  grpc_channel_args channel_args;
  channel_args.args = args;
  channel_args.num_args = num_args;

  grpc_ssl_pem_key_cert_pair client_credentials;
  grpc_ssl_pem_key_cert_pair *client_credentials_pointer = NULL;
  if (client_certs != NULL && client_private_key != NULL) {
    client_credentials.cert_chain = client_certs;
    client_credentials.private_key = client_private_key;
    client_credentials_pointer = &client_credentials;
  }
  grpc_channel_credentials *creds = grpc_ssl_credentials_create(pem_root_certs, client_credentials_pointer, NULL);

  c->channel = grpc_secure_channel_create(creds, address, &channel_args, NULL);
  c->completion_queue = grpc_completion_queue_create_for_next(NULL);

  grpc_channel_credentials_release(creds);

  return c;
}

cgrpc_channel *cgrpc_channel_create_google(const char *address,
                                           grpc_arg *args,
                                           int num_args) {
  cgrpc_channel *c = (cgrpc_channel *) gpr_zalloc(sizeof (cgrpc_channel));

  grpc_channel_args channel_args;
  channel_args.args = args;
  channel_args.num_args = num_args;

  grpc_channel_credentials *google_creds = grpc_google_default_credentials_create();

  c->channel = grpc_secure_channel_create(google_creds, address, &channel_args, NULL);
  c->completion_queue = grpc_completion_queue_create_for_next(NULL);

  grpc_channel_credentials_release(google_creds);

  return c;
}


void cgrpc_channel_destroy(cgrpc_channel *c) {
  grpc_channel_destroy(c->channel);
  c->channel = NULL;
  gpr_free(c);
}

cgrpc_call *cgrpc_channel_create_call(cgrpc_channel *channel,
                                      const char *method,
                                      const char *host,
                                      double timeout) {
  // create call
  grpc_slice host_slice = grpc_slice_from_copied_string(host);
  grpc_slice method_slice = grpc_slice_from_copied_string(method);
  gpr_timespec deadline = cgrpc_deadline_in_seconds_from_now(timeout);
  // The resulting call will have a retain call of +1. We'll release it in `cgrpc_call_destroy()`.
  grpc_call *channel_call = grpc_channel_create_call(channel->channel,
                                                     NULL,
                                                     GRPC_PROPAGATE_DEFAULTS,
                                                     channel->completion_queue,
                                                     method_slice,
                                                     &host_slice,
                                                     deadline,
                                                     NULL);
  grpc_slice_unref(host_slice);
  grpc_slice_unref(method_slice);
  cgrpc_call *call = (cgrpc_call *) gpr_zalloc(sizeof(cgrpc_call));
  call->call = channel_call;
  return call;
}

cgrpc_completion_queue *cgrpc_channel_completion_queue(cgrpc_channel *channel) {
  return channel->completion_queue;
}

grpc_connectivity_state cgrpc_channel_check_connectivity_state(cgrpc_channel *channel, int try_to_connect) {
  return grpc_channel_check_connectivity_state(channel->channel, try_to_connect);
}

void cgrpc_channel_watch_connectivity_state(cgrpc_channel *channel, cgrpc_completion_queue *completion_queue, grpc_connectivity_state last_observed_state, double deadline, void *tag) {
  gpr_timespec deadline_seconds = cgrpc_deadline_in_seconds_from_now(deadline);
  return grpc_channel_watch_connectivity_state(channel->channel, last_observed_state, deadline_seconds, completion_queue, tag);
}
