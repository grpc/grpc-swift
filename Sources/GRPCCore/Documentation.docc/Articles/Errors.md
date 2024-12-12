# Errors

Learn about the different error mechanisms in gRPC and how to use them.

## Overview

gRPC has a well defined error model for RPCs and a common extension to provide
richer errors when using Protocol Buffers. This article explains both mechanisms
and offers advice on using and handling RPC errors for service authors and
clients.

### Error models

gRPC has two widely used error models:

1. A 'standard' error model supported by all client/server gRPC libraries.
2. A 'rich' error model providing more detailed error information via serialized
   Protocol Buffers messages.

#### Standard error model

In gRPC the outcome of every RPC is represented by a status made up of a code
and a message. The status is propagated from the server to the client in the
metadata as the final part of an RPC indicating the outcome of the RPC.

You can find more information about the error codes in ``RPCError/Code`` and in
the status codes guide on the
[gRPC website](https://grpc.io/docs/guides/status-codes/).

This mechanism is part of the gRPC protocol is supported by all client/server
gRPC libraries regardless of the data format (e.g. Protocol Buffers) being used
for messages.

#### Rich error model

The standard error model is quite limited and doesn't include the ability to
communicate details about the error. If you're using the Protocol Buffers data
format for messages then you may wish to use the "rich" error model.

The model was developed and used by Google and is described in more detail
in the [gRPC error guide](https://grpc.io/docs/guides/error/) and
[Google AIP-193](https://google.aip.dev/193).

While not officially part of gRPC it's a widely used convention with support in
various client/server gRPC libraries, including gRPC Swift.

It specifies a standard set of error message types covering the most common
situations. The error details are encoded as protobuf messages in the trailing
metadata of an RPC. Clients are able to deserialize and access the details as
type-safe structured messages should they need to.

### User guide

Learn how to use both models in gRPC Swift.

#### Service authors

Errors thrown from an RPC handler are caught by the gRPC runtime and turned into
a status. You have a two options to ensure that an appropriate status is sent to
the client if your RPC handler throws an error:

1. Throw an ``RPCError`` which explicitly sets the desired status code and
   message.
2. Throw an error conforming to ``RPCErrorConvertible`` which the gRPC runtime
   will use to create an ``RPCError``.

Any errors thrown which don't fall into these categories will result in a status
code of `unknown` being sent to the client.

Generally speaking expected failure scenarios should be considered as part of
the API contract and each RPC should be documented accordingly.

#### Clients

Clients should catch ``RPCError`` if they are interested in the failures from an
RPC. This is a manifestation of the error sent by the server but in some cases
it may be synthesized locally.

For clients using the rich error model, the ``RPCError`` can be caught and a
detailed error can be extracted from it using `unpackGoogleRPCStatus()`.

See [`error-details`](https://github.com/grpc/grpc-swift/tree/main/Examples) for
an examples.
