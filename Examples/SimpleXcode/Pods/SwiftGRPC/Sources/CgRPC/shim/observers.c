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

// create observers for each type of GRPC operation

cgrpc_observer_send_initial_metadata *cgrpc_observer_create_send_initial_metadata(cgrpc_metadata_array *metadata) {
  cgrpc_observer_send_initial_metadata *observer =
  (cgrpc_observer_send_initial_metadata *) malloc(sizeof (cgrpc_observer_send_initial_metadata));
  observer->op_type = GRPC_OP_SEND_INITIAL_METADATA;
  cgrpc_metadata_array_move_metadata(&(observer->initial_metadata), metadata);
  return observer;
}

cgrpc_observer_send_message *cgrpc_observer_create_send_message() {
  cgrpc_observer_send_message *observer =
  (cgrpc_observer_send_message *) malloc(sizeof (cgrpc_observer_send_message));
  observer->op_type = GRPC_OP_SEND_MESSAGE;
  return observer;
}

cgrpc_observer_send_close_from_client *cgrpc_observer_create_send_close_from_client() {
  cgrpc_observer_send_close_from_client *observer =
  (cgrpc_observer_send_close_from_client *) malloc(sizeof (cgrpc_observer_send_close_from_client));
  observer->op_type = GRPC_OP_SEND_CLOSE_FROM_CLIENT;
  return observer;
}

cgrpc_observer_send_status_from_server *cgrpc_observer_create_send_status_from_server(cgrpc_metadata_array *metadata) {
  cgrpc_observer_send_status_from_server *observer =
  (cgrpc_observer_send_status_from_server *) malloc(sizeof (cgrpc_observer_send_status_from_server));
  observer->op_type = GRPC_OP_SEND_STATUS_FROM_SERVER;
  cgrpc_metadata_array_move_metadata(&(observer->trailing_metadata), metadata);
  return observer;
}

cgrpc_observer_recv_initial_metadata *cgrpc_observer_create_recv_initial_metadata() {
  cgrpc_observer_recv_initial_metadata *observer =
  (cgrpc_observer_recv_initial_metadata *) malloc(sizeof (cgrpc_observer_recv_initial_metadata));
  observer->op_type = GRPC_OP_RECV_INITIAL_METADATA;
  return observer;
}

cgrpc_observer_recv_message *cgrpc_observer_create_recv_message() {
  cgrpc_observer_recv_message *observer =
  (cgrpc_observer_recv_message *) malloc(sizeof (cgrpc_observer_recv_message));
  observer->op_type = GRPC_OP_RECV_MESSAGE;
  observer->response_payload_recv = NULL;
  return observer;
}

cgrpc_observer_recv_status_on_client *cgrpc_observer_create_recv_status_on_client() {
  cgrpc_observer_recv_status_on_client *observer =
  (cgrpc_observer_recv_status_on_client *) malloc(sizeof (cgrpc_observer_recv_status_on_client));
  observer->op_type = GRPC_OP_RECV_STATUS_ON_CLIENT;
  return observer;
}

cgrpc_observer_recv_close_on_server *cgrpc_observer_create_recv_close_on_server() {
  cgrpc_observer_recv_close_on_server *observer =
  (cgrpc_observer_recv_close_on_server *) malloc(sizeof (cgrpc_observer_recv_close_on_server));
  observer->op_type = GRPC_OP_RECV_CLOSE_ON_SERVER;
  observer->was_cancelled = 0;
  return observer;
}

// apply observer to operation

void cgrpc_observer_apply(cgrpc_observer *observer, grpc_op *op) {
  op->op = observer->op_type;
  op->flags = 0;
  op->reserved = NULL;

  switch (observer->op_type) {
    case GRPC_OP_SEND_INITIAL_METADATA: {
      cgrpc_observer_send_initial_metadata *obs = (cgrpc_observer_send_initial_metadata *) observer;
      op->data.send_initial_metadata.count = obs->initial_metadata.count;
      op->data.send_initial_metadata.metadata = obs->initial_metadata.metadata;
      break;
    }
    case GRPC_OP_SEND_MESSAGE: {
      cgrpc_observer_send_message *obs = (cgrpc_observer_send_message *) observer;
      op->data.send_message.send_message = obs->request_payload;
      break;
    }
    case GRPC_OP_SEND_CLOSE_FROM_CLIENT: {
      break;
    }
    case GRPC_OP_SEND_STATUS_FROM_SERVER: {
      cgrpc_observer_send_status_from_server *obs = (cgrpc_observer_send_status_from_server *) observer;
      op->data.send_status_from_server.trailing_metadata_count = obs->trailing_metadata.count;
      op->data.send_status_from_server.trailing_metadata = obs->trailing_metadata.metadata;
      op->data.send_status_from_server.status = obs->status;
      op->data.send_status_from_server.status_details = &obs->status_details;
      break;
    }
    case GRPC_OP_RECV_INITIAL_METADATA: {
      cgrpc_observer_recv_initial_metadata *obs = (cgrpc_observer_recv_initial_metadata *) observer;
      grpc_metadata_array_init(&(obs->initial_metadata_recv));
      op->data.recv_initial_metadata.recv_initial_metadata = &(obs->initial_metadata_recv);
      break;
    }
    case GRPC_OP_RECV_MESSAGE: {
      cgrpc_observer_recv_message *obs = (cgrpc_observer_recv_message *) observer;
      op->data.recv_message.recv_message = &(obs->response_payload_recv);
      break;
    }
    case GRPC_OP_RECV_STATUS_ON_CLIENT: {
      cgrpc_observer_recv_status_on_client *obs = (cgrpc_observer_recv_status_on_client *) observer;
      grpc_metadata_array_init(&(obs->trailing_metadata_recv));
      obs->server_status = GRPC_STATUS_OK;
      obs->server_details = grpc_slice_from_copied_string("");
      op->data.recv_status_on_client.trailing_metadata = &(obs->trailing_metadata_recv);
      op->data.recv_status_on_client.status = &(obs->server_status);
      op->data.recv_status_on_client.status_details = &(obs->server_details);
      break;
    }
    case GRPC_OP_RECV_CLOSE_ON_SERVER: {
      cgrpc_observer_recv_close_on_server *obs = (cgrpc_observer_recv_close_on_server *) observer;
      op->data.recv_close_on_server.cancelled = &(obs->was_cancelled);
      break;
    }
    default: {

    }
  }
}

// destroy all observers

void cgrpc_observer_destroy(cgrpc_observer *observer) {
  switch (observer->op_type) {
    case GRPC_OP_SEND_INITIAL_METADATA: {
      cgrpc_observer_send_initial_metadata *obs = (cgrpc_observer_send_initial_metadata *) observer;
      grpc_metadata_array_destroy(&(obs->initial_metadata));
      free(obs);
      break;
    }
    case GRPC_OP_SEND_MESSAGE: {
      cgrpc_observer_send_message *obs = (cgrpc_observer_send_message *) observer;
      grpc_byte_buffer_destroy(obs->request_payload);
      free(obs);
      break;
    }
    case GRPC_OP_SEND_CLOSE_FROM_CLIENT: {
      cgrpc_observer_send_close_from_client *obs = (cgrpc_observer_send_close_from_client *) observer;
      free(obs);
      break;
    }
    case GRPC_OP_SEND_STATUS_FROM_SERVER: {
      cgrpc_observer_send_status_from_server *obs = (cgrpc_observer_send_status_from_server *) observer;
      grpc_slice_unref(obs->status_details);
      free(obs);
      break;
    }
    case GRPC_OP_RECV_INITIAL_METADATA: {
      cgrpc_observer_recv_initial_metadata *obs = (cgrpc_observer_recv_initial_metadata *) observer;
      grpc_metadata_array_destroy(&obs->initial_metadata_recv);
      free(obs);
      break;
    }
    case GRPC_OP_RECV_MESSAGE: {
      cgrpc_observer_recv_message *obs = (cgrpc_observer_recv_message *) observer;
      grpc_byte_buffer_destroy(obs->response_payload_recv);
      free(obs);
      break;
    }
    case GRPC_OP_RECV_STATUS_ON_CLIENT: {
      cgrpc_observer_recv_status_on_client *obs = (cgrpc_observer_recv_status_on_client *) observer;
      grpc_metadata_array_destroy(&(obs->trailing_metadata_recv));
      grpc_slice_unref(obs->server_details);
      free(obs);
      break;
    }
    case GRPC_OP_RECV_CLOSE_ON_SERVER: {
      cgrpc_observer_recv_close_on_server *obs = (cgrpc_observer_recv_close_on_server *) observer;
      free(obs);
      break;
    }
    default: {

    }
  }
}

cgrpc_byte_buffer *cgrpc_observer_recv_message_get_message(cgrpc_observer_recv_message *observer) {
  if (observer->response_payload_recv) {
    return grpc_byte_buffer_copy(observer->response_payload_recv);
  } else {
    return NULL;
  }
}

cgrpc_metadata_array *cgrpc_observer_recv_initial_metadata_get_metadata(cgrpc_observer_recv_initial_metadata *observer) {
  cgrpc_metadata_array *metadata = cgrpc_metadata_array_create();
  cgrpc_metadata_array_move_metadata(metadata, &(observer->initial_metadata_recv));
  return metadata;
}

void cgrpc_observer_send_message_set_message(cgrpc_observer_send_message *observer, cgrpc_byte_buffer *message) {
  observer->request_payload = grpc_byte_buffer_copy(message);
}

void cgrpc_observer_send_status_from_server_set_status(cgrpc_observer_send_status_from_server *observer, int status) {
  observer->status = status;
}

void cgrpc_observer_send_status_from_server_set_status_details(cgrpc_observer_send_status_from_server *observer, const char *statusDetails) {
  observer->status_details = grpc_slice_from_copied_string(statusDetails);
}

cgrpc_metadata_array *cgrpc_observer_recv_status_on_client_get_metadata(cgrpc_observer_recv_status_on_client *observer) {
  cgrpc_metadata_array *metadata = cgrpc_metadata_array_create();
  cgrpc_metadata_array_move_metadata(metadata, &(observer->trailing_metadata_recv));
  return metadata;
}

long cgrpc_observer_recv_status_on_client_get_status(cgrpc_observer_recv_status_on_client *observer) {
  return observer->server_status;
}

char *cgrpc_observer_recv_status_on_client_copy_status_details(cgrpc_observer_recv_status_on_client *observer) {
  size_t length = GRPC_SLICE_LENGTH(observer->server_details);
  char *str = (char *) malloc(length + 1);
  memcpy(str, GRPC_SLICE_START_PTR(observer->server_details), length);
  str[length] = 0;
  return str;
}

int cgrpc_observer_recv_close_on_server_get_was_cancelled(cgrpc_observer_recv_close_on_server *observer) {
  return observer->was_cancelled;
}

