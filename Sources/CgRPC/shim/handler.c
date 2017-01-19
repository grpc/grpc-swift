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

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

cgrpc_handler *cgrpc_handler_create_with_server(cgrpc_server *server) {
  cgrpc_handler *handler = (cgrpc_handler *) malloc(sizeof (cgrpc_handler));
  memset(handler, 0, sizeof(cgrpc_handler));
  handler->server = server;
  grpc_metadata_array_init(&(handler->request_metadata_recv));
  grpc_call_details_init(&(handler->call_details));
  handler->completion_queue = grpc_completion_queue_create(NULL);
  return handler;
}

void cgrpc_handler_destroy(cgrpc_handler *h) {
  grpc_completion_queue_shutdown(h->completion_queue);
  cgrpc_completion_queue_drain(h->completion_queue);
  grpc_completion_queue_destroy(h->completion_queue);
  grpc_metadata_array_destroy(&(h->request_metadata_recv));
  grpc_call_details_destroy(&(h->call_details));
  if (h->server_call) {
    grpc_call_destroy(h->server_call);
  }
  free(h);
}

const char *cgrpc_handler_host(cgrpc_handler *h) {
  return h->call_details.host;
}

const char *cgrpc_handler_method(cgrpc_handler *h) {
  return h->call_details.method;
}

const char *cgrpc_handler_call_peer(cgrpc_handler *h) {
  return grpc_call_get_peer(h->server_call);
}

cgrpc_call *cgrpc_handler_get_call(cgrpc_handler *h) {
  cgrpc_call *call = (cgrpc_call *) malloc(sizeof(cgrpc_call));
  memset(call, 0, sizeof(cgrpc_call));
  call->call = h->server_call;
  return call;
}

cgrpc_completion_queue *cgrpc_handler_get_completion_queue(cgrpc_handler *h) {
  return h->completion_queue;
}

grpc_call_error cgrpc_handler_request_call(cgrpc_handler *h,
                                           cgrpc_metadata_array *metadata,
                                           long tag) {
  return grpc_server_request_call(h->server->server,
                                  &(h->server_call),
                                  &(h->call_details),
                                  metadata,
                                  h->completion_queue,
                                  h->server->completion_queue,
                                  cgrpc_create_tag(tag));
}


