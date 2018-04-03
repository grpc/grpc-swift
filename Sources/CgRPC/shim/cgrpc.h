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
#ifndef cgrpc_h
#define cgrpc_h

#include <stdlib.h>

// This file lists C functions and types used to build Swift gRPC support

#ifndef cgrpc_internal_h
// all domain types are opaque pointers
typedef void cgrpc_byte_buffer;
typedef void cgrpc_call;
typedef void cgrpc_channel;
typedef void cgrpc_completion_queue;
typedef void cgrpc_handler;
typedef void cgrpc_metadata;
typedef void cgrpc_metadata_array;
typedef void cgrpc_mutex;
typedef void cgrpc_observer;
typedef void cgrpc_observer_send_initial_metadata;
typedef void cgrpc_observer_send_message;
typedef void cgrpc_observer_send_close_from_client;
typedef void cgrpc_observer_send_status_from_server;
typedef void cgrpc_observer_recv_initial_metadata;
typedef void cgrpc_observer_recv_message;
typedef void cgrpc_observer_recv_status_on_client;
typedef void cgrpc_observer_recv_close_on_server;
typedef void cgrpc_operations;
typedef void cgrpc_server;

/** Result of a grpc call. If the caller satisfies the prerequisites of a
 particular operation, the grpc_call_error returned will be GRPC_CALL_OK.
 Receiving any other value listed here is an indication of a bug in the
 caller. */
typedef enum grpc_call_error {
  /** everything went ok */
  GRPC_CALL_OK = 0,
  /** something failed, we don't know what */
  GRPC_CALL_ERROR,
  /** this method is not available on the server */
  GRPC_CALL_ERROR_NOT_ON_SERVER,
  /** this method is not available on the client */
  GRPC_CALL_ERROR_NOT_ON_CLIENT,
  /** this method must be called before server_accept */
  GRPC_CALL_ERROR_ALREADY_ACCEPTED,
  /** this method must be called before invoke */
  GRPC_CALL_ERROR_ALREADY_INVOKED,
  /** this method must be called after invoke */
  GRPC_CALL_ERROR_NOT_INVOKED,
  /** this call is already finished
   (writes_done or write_status has already been called) */
  GRPC_CALL_ERROR_ALREADY_FINISHED,
  /** there is already an outstanding read/write operation on the call */
  GRPC_CALL_ERROR_TOO_MANY_OPERATIONS,
  /** the flags value was illegal for this call */
  GRPC_CALL_ERROR_INVALID_FLAGS,
  /** invalid metadata was passed to this call */
  GRPC_CALL_ERROR_INVALID_METADATA,
  /** invalid message was passed to this call */
  GRPC_CALL_ERROR_INVALID_MESSAGE,
  /** completion queue for notification has not been registered with the
   server */
  GRPC_CALL_ERROR_NOT_SERVER_COMPLETION_QUEUE,
  /** this batch of operations leads to more operations than allowed */
  GRPC_CALL_ERROR_BATCH_TOO_BIG,
  /** payload type requested is not the type registered */
  GRPC_CALL_ERROR_PAYLOAD_TYPE_MISMATCH
} grpc_call_error;

/** The type of completion (for grpc_event) */
typedef enum grpc_completion_type {
  /** Shutting down */
  GRPC_QUEUE_SHUTDOWN,
  /** No event before timeout */
  GRPC_QUEUE_TIMEOUT,
  /** Operation completion */
  GRPC_OP_COMPLETE
} grpc_completion_type;

/** Connectivity state of a channel. */
typedef enum grpc_connectivity_state {
  /** channel has just been initialized */
  GRPC_CHANNEL_INIT = -1,
  /** channel is idle */
  GRPC_CHANNEL_IDLE,
  /** channel is connecting */
  GRPC_CHANNEL_CONNECTING,
  /** channel is ready for work */
  GRPC_CHANNEL_READY,
  /** channel has seen a failure but expects to recover */
  GRPC_CHANNEL_TRANSIENT_FAILURE,
  /** channel has seen a failure that it cannot recover from */
  GRPC_CHANNEL_SHUTDOWN
} grpc_connectivity_state;

typedef struct grpc_event {
  /** The type of the completion. */
  grpc_completion_type type;
  /** non-zero if the operation was successful, 0 upon failure.
   Only GRPC_OP_COMPLETE can succeed or fail. */
  int success;
  /** The tag passed to grpc_call_start_batch etc to start this operation.
   Only GRPC_OP_COMPLETE has a tag. */
  void *tag;
} grpc_event;

typedef enum grpc_arg_type {
  GRPC_ARG_STRING,
  GRPC_ARG_INTEGER,
  GRPC_ARG_POINTER
} grpc_arg_type;

typedef struct grpc_arg_pointer_vtable {
  void *(*copy)(void *p);
  void (*destroy)(void *p);
  int (*cmp)(void *p, void *q);
} grpc_arg_pointer_vtable;

typedef struct grpc_arg {
  grpc_arg_type type;
  char *key;
  union grpc_arg_value {
    char *string;
    int integer;
    struct grpc_arg_pointer {
      void *p;
      const grpc_arg_pointer_vtable *vtable;
    } pointer;
  } value;
} grpc_arg;

#endif

// directly expose a few grpc library functions
void grpc_init(void);
void grpc_shutdown(void);
const char *grpc_version_string(void);
const char *grpc_g_stands_for(void);

char *gpr_strdup(const char *src);

void cgrpc_completion_queue_drain(cgrpc_completion_queue *cq);
void grpc_completion_queue_destroy(cgrpc_completion_queue *cq);

// helper
void cgrpc_free_copied_string(char *string);

// channel support
cgrpc_channel *cgrpc_channel_create(const char *address, 
                                    grpc_arg *args,
                                    int num_args);
cgrpc_channel *cgrpc_channel_create_secure(const char *address,
                                           const char *pem_root_certs,
                                           grpc_arg *args,
                                           int num_args);

void cgrpc_channel_destroy(cgrpc_channel *channel);
cgrpc_call *cgrpc_channel_create_call(cgrpc_channel *channel,
                                      const char *method,
                                      const char *host,
                                      double timeout);
cgrpc_completion_queue *cgrpc_channel_completion_queue(cgrpc_channel *channel);

grpc_connectivity_state cgrpc_channel_check_connectivity_state(
    cgrpc_channel *channel, int try_to_connect);

// server support
cgrpc_server *cgrpc_server_create(const char *address);
cgrpc_server *cgrpc_server_create_secure(const char *address,
                                         const char *private_key,
                                         const char *cert_chain);
void cgrpc_server_stop(cgrpc_server *server);
void cgrpc_server_destroy(cgrpc_server *s);
void cgrpc_server_start(cgrpc_server *s);
cgrpc_completion_queue *cgrpc_server_get_completion_queue(cgrpc_server *s);

// completion queues
grpc_event cgrpc_completion_queue_get_next_event(cgrpc_completion_queue *cq,
                                                 double timeout);
void cgrpc_completion_queue_drain(cgrpc_completion_queue *cq);
void cgrpc_completion_queue_shutdown(cgrpc_completion_queue *cq);

// server request handlers
cgrpc_handler *cgrpc_handler_create_with_server(cgrpc_server *server);
void cgrpc_handler_destroy(cgrpc_handler *h);
cgrpc_call *cgrpc_handler_get_call(cgrpc_handler *h);
cgrpc_completion_queue *cgrpc_handler_get_completion_queue(cgrpc_handler *h);

grpc_call_error cgrpc_handler_request_call(cgrpc_handler *h,
                                           cgrpc_metadata_array *metadata,
                                           long tag);
char *cgrpc_handler_copy_host(cgrpc_handler *h);
char *cgrpc_handler_copy_method(cgrpc_handler *h);
char *cgrpc_handler_call_peer(cgrpc_handler *h);

// call support
void cgrpc_call_destroy(cgrpc_call *call);
grpc_call_error cgrpc_call_perform(cgrpc_call *call, cgrpc_operations *operations, int64_t tag);
void cgrpc_call_cancel(cgrpc_call *call);

// operations
cgrpc_operations *cgrpc_operations_create(void);
void cgrpc_operations_destroy(cgrpc_operations *operations);
void cgrpc_operations_reserve_space_for_operations(cgrpc_operations *call, int max_operations);
void cgrpc_operations_add_operation(cgrpc_operations *call, cgrpc_observer *observer);

// metadata support
cgrpc_metadata_array *cgrpc_metadata_array_create(void);
void cgrpc_metadata_array_destroy(cgrpc_metadata_array *array);
size_t cgrpc_metadata_array_get_count(cgrpc_metadata_array *array);
char *cgrpc_metadata_array_copy_key_at_index(cgrpc_metadata_array *array, size_t index);
char *cgrpc_metadata_array_copy_value_at_index(cgrpc_metadata_array *array, size_t index);
void cgrpc_metadata_array_move_metadata(cgrpc_metadata_array *dest, cgrpc_metadata_array *src);
void cgrpc_metadata_array_append_metadata(cgrpc_metadata_array *metadata, const char *key, const char *value);

// mutex support
cgrpc_mutex *cgrpc_mutex_create(void);
void cgrpc_mutex_destroy(cgrpc_mutex *mu);
void cgrpc_mutex_lock(cgrpc_mutex *mu);
void cgrpc_mutex_unlock(cgrpc_mutex *mu);

// byte buffer support
void cgrpc_byte_buffer_destroy(cgrpc_byte_buffer *bb);
cgrpc_byte_buffer *cgrpc_byte_buffer_create_by_copying_data(const void *source, size_t len);
const void *cgrpc_byte_buffer_copy_data(cgrpc_byte_buffer *bb, size_t *length);

// event support
int64_t cgrpc_event_tag(grpc_event ev);

// observers

// constructors
cgrpc_observer_send_initial_metadata   *cgrpc_observer_create_send_initial_metadata(cgrpc_metadata_array *metadata);
cgrpc_observer_send_message            *cgrpc_observer_create_send_message(void);
cgrpc_observer_send_close_from_client  *cgrpc_observer_create_send_close_from_client(void);
cgrpc_observer_send_status_from_server *cgrpc_observer_create_send_status_from_server(cgrpc_metadata_array *metadata);
cgrpc_observer_recv_initial_metadata   *cgrpc_observer_create_recv_initial_metadata(void);
cgrpc_observer_recv_message            *cgrpc_observer_create_recv_message(void);
cgrpc_observer_recv_status_on_client   *cgrpc_observer_create_recv_status_on_client(void);
cgrpc_observer_recv_close_on_server    *cgrpc_observer_create_recv_close_on_server(void);

// destructor
void cgrpc_observer_destroy(cgrpc_observer *observer);

// GRPC_OP_SEND_INITIAL_METADATA


// GRPC_OP_SEND_MESSAGE
void cgrpc_observer_send_message_set_message(cgrpc_observer_send_message *observer,
                                             cgrpc_byte_buffer *message);

// GRPC_OP_SEND_CLOSE_FROM_CLIENT
// -- no special handlers --

// GRPC_OP_SEND_STATUS_FROM_SERVER
void cgrpc_observer_send_status_from_server_set_status
(cgrpc_observer_send_status_from_server *observer,
 int status);

void cgrpc_observer_send_status_from_server_set_status_details
(cgrpc_observer_send_status_from_server *observer,
 const char *statusDetails);

// GRPC_OP_RECV_INITIAL_METADATA
cgrpc_metadata_array *cgrpc_observer_recv_initial_metadata_get_metadata
(cgrpc_observer_recv_initial_metadata *observer);

// GRPC_OP_RECV_MESSAGE
cgrpc_byte_buffer *cgrpc_observer_recv_message_get_message
(cgrpc_observer_recv_message *observer);

// GRPC_OP_RECV_STATUS_ON_CLIENT
cgrpc_metadata_array *cgrpc_observer_recv_status_on_client_get_metadata
(cgrpc_observer_recv_status_on_client *observer);

long cgrpc_observer_recv_status_on_client_get_status
(cgrpc_observer_recv_status_on_client *observer);

char *cgrpc_observer_recv_status_on_client_copy_status_details
(cgrpc_observer_recv_status_on_client *observer);

// GRPC_OP_RECV_CLOSE_ON_SERVER
int cgrpc_observer_recv_close_on_server_was_cancelled
(cgrpc_observer_recv_close_on_server *observer);

#endif
