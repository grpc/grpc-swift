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
#ifndef cgrpc_internal_h
#define cgrpc_internal_h

#include <grpc/grpc.h>
#include <grpc/grpc_security.h>
#include <grpc/byte_buffer_reader.h>

typedef struct {
  grpc_call *call; // owned
} cgrpc_call;

typedef struct {
  grpc_op *ops; // owned
  int ops_count;
} cgrpc_operations;

typedef struct {
  grpc_channel *channel; // owned
  grpc_completion_queue *completion_queue; // owned
} cgrpc_channel;

typedef struct {
  grpc_server *server; // owned
  grpc_completion_queue *completion_queue; // owned
  int port;
} cgrpc_server;

typedef struct {
  cgrpc_server *server; // reference
  grpc_completion_queue *completion_queue; // owned; handlers have dedicated completion queues
  grpc_metadata_array request_metadata_recv;
  grpc_call_details call_details;
  grpc_call *server_call; // owned
} cgrpc_handler;

typedef grpc_byte_buffer cgrpc_byte_buffer;
typedef grpc_completion_queue cgrpc_completion_queue;
typedef grpc_metadata cgrpc_metadata;
typedef grpc_metadata_array cgrpc_metadata_array;
typedef gpr_mu cgrpc_mutex;

// OPERATIONS

typedef struct {
  grpc_op_type op_type;
} cgrpc_observer;

typedef struct {
  grpc_op_type op_type;
  grpc_metadata_array initial_metadata;
} cgrpc_observer_send_initial_metadata;

typedef struct {
  grpc_op_type op_type;
  grpc_byte_buffer *request_payload;
} cgrpc_observer_send_message;

typedef struct {
  grpc_op_type op_type;
} cgrpc_observer_send_close_from_client;

typedef struct {
  grpc_op_type op_type;
  grpc_metadata_array trailing_metadata;
  grpc_status_code status;
  grpc_slice status_details;
} cgrpc_observer_send_status_from_server;

typedef struct {
  grpc_op_type op_type;
  grpc_metadata_array initial_metadata_recv;
} cgrpc_observer_recv_initial_metadata;

typedef struct {
  grpc_op_type op_type;
  grpc_byte_buffer *response_payload_recv;
} cgrpc_observer_recv_message;

typedef struct {
  grpc_op_type op_type;
  grpc_metadata_array trailing_metadata_recv;
  grpc_status_code server_status;
  grpc_slice server_details;
  size_t server_details_capacity;
} cgrpc_observer_recv_status_on_client;

typedef struct {
  grpc_op_type op_type;
  int was_cancelled;
} cgrpc_observer_recv_close_on_server;

// internal utilities
void *cgrpc_create_tag(void *t);
gpr_timespec cgrpc_deadline_in_seconds_from_now(float seconds);

void cgrpc_observer_apply(cgrpc_observer *observer, grpc_op *op);

#endif /* cgrpc_internal_h */
