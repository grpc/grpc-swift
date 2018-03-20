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

#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

cgrpc_server *cgrpc_server_create(const char *address) {
  cgrpc_server *server = (cgrpc_server *) malloc(sizeof (cgrpc_server));
  server->server = grpc_server_create(NULL, NULL);
  server->completion_queue = grpc_completion_queue_create_for_next(NULL);
  grpc_server_register_completion_queue(server->server, server->completion_queue, NULL);
  // prepare the server to listen
  server->port = grpc_server_add_insecure_http2_port(server->server, address);
  return server;
}

cgrpc_server *cgrpc_server_create_secure(const char *address,
                                         const char *private_key,
                                         const char *cert_chain) {
  cgrpc_server *server = (cgrpc_server *) malloc(sizeof (cgrpc_server));
  server->server = grpc_server_create(NULL, NULL);
  server->completion_queue = grpc_completion_queue_create_for_next(NULL);
  grpc_server_register_completion_queue(server->server, server->completion_queue, NULL);

  grpc_ssl_pem_key_cert_pair server_credentials;
  server_credentials.private_key = private_key;
  server_credentials.cert_chain = cert_chain;

  grpc_server_credentials *credentials = grpc_ssl_server_credentials_create
  (NULL,
   &server_credentials,
   1,
   0,
   NULL);
  
  // prepare the server to listen
  server->port = grpc_server_add_secure_http2_port(server->server, address, credentials);
  return server;
}

void cgrpc_server_stop(cgrpc_server *server) {
  grpc_server_shutdown_and_notify(server->server,
                                  server->completion_queue,
                                  cgrpc_create_tag(0));
}

void cgrpc_server_destroy(cgrpc_server *server) {
  grpc_server_shutdown_and_notify(server->server,
                                  server->completion_queue,
                                  cgrpc_create_tag(1000));
  while (1) {
    double timeout = 5;
    gpr_timespec deadline = cgrpc_deadline_in_seconds_from_now(timeout);
    grpc_event completion_event = grpc_completion_queue_next(server->completion_queue, deadline, NULL);
    if (completion_event.type == GRPC_OP_COMPLETE) {
      break;
    }
  }
  grpc_server_destroy(server->server);
  server->server = NULL;
}

void cgrpc_server_start(cgrpc_server *server) {
  grpc_server_start(server->server);
}

cgrpc_completion_queue *cgrpc_server_get_completion_queue(cgrpc_server *s) {
  return s->completion_queue;
}
