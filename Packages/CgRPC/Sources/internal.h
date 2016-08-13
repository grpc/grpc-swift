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
#ifndef cgrpc_internal_h
#define cgrpc_internal_h

#include <grpc/grpc.h>
#include <grpc/grpc_security.h>
#include <grpc/byte_buffer_reader.h>
#include <grpc/impl/codegen/alloc.h>

typedef struct {
  grpc_call *call; // owned
  grpc_op *ops; // owned
  int ops_count;
} cgrpc_call;

typedef struct {
  grpc_channel *client; // owned
  grpc_completion_queue *completion_queue; // owned
} cgrpc_client;

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
  char *status_details;
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
  char *server_details;
  size_t server_details_capacity;
} cgrpc_observer_recv_status_on_client;

typedef struct {
  grpc_op_type op_type;
  int was_cancelled;
} cgrpc_observer_recv_close_on_server;

// internal utilities
void *cgrpc_create_tag(intptr_t t);
gpr_timespec cgrpc_deadline_in_seconds_from_now(float seconds);

void cgrpc_observer_apply(cgrpc_observer *observer, grpc_op *op);

#endif /* cgrpc_internal_h */
