# Public API

Understand what constitutes the public API of gRPC Swift and the commitments
made by the maintainers.

## Overview

The gRPC Swift project uses [Semantic Versioning 2.0.0][0] which requires
projects to declare their public API. This document describes what is and isn't
part of the public API; commitments the maintainers make relating to the API,
and guidelines for users.

For clarity, the project is comprised of the following Swift packages:

- [grpc/grpc-swift][1],
- [grpc/grpc-swift-nio-transport][2],
- [grpc/grpc-swift-protobuf][3], and
- [grpc/grpc-swift-extras][4].

## What _is_ and _isn't_ public API

### Library targets

All library targets made available as package products are considered to be
public API. Examples of these include `GRPCCore` and `GRPCProtobuf`.

> Exceptions:
> Targets with names starting with an underscore (`_`) aren't public API.

### Symbols

All publicly exposed symbols (i.e. symbols which are declared as `public`)
within public library targets or those which are re-exported from non-public
targets are part of the public API. Examples include `Metadata`,
`ServiceConfig`, and `GRPCServer`.

> Exceptions:
> - Symbols starting with an underscore (`_`), for example `_someFunction()` and
>   `_AnotherType` aren't public API.
> - Initializers where the first character of the first parameter label is an
>   underscore, for example `init(_foo:)` aren't public API.

### Configuration and inputs

Any configuration, input, and interfaces to executable products which have
inputs (such as command line arguments, or configuration files) are considered
to be public API. Examples of these include the configuration file passed to the
Swift Package Manager build plugin for generating stubs provided by
[grpc-swift-protobuf][3].

> Exceptions:
> - Executable _targets_ which aren't exposed as executable _products_.

## Commitments made by the maintainers

Without releasing a new major version, the gRPC Swift maintainers commit to not
adding any new types to the global namespace without a "GRPC" prefix.

To illustrate this, the maintainers may:
1. Add a new type to an existing module called `GRPCPanCakes` but will not add a
   new type called `PanCakes` to an existing module.
2. Add a new top-level function to an existing module called `grpcRun()` but
   won't add a new top-level function called `run()`.
3. Add a new module called `GRPCFoo`. Any symbols added to the new module at the
   point the module becomes API aren't required to have a "GRPC" prefix; symbols
   added after that point will be prefixed as required by (1) and (2).

This allows the project to follow Semantic versioning without breaking adopter
code in minor and patch releases.

## Guidelines for users

In order to not have your code broken by a gRPC Swift update you should only use
the public API as described above. There are a number of other guidelines you
should follow as well:

1. You _may_ conform your own types to protocols provided by gRPC Swift.
2. You _may_ conform types provided by gRPC Swift to your own protocols.
3. You _mustn't_ conform types provided by gRPC Swift to protocols that you
   don't own, and you mustn't conform types you don't own to protocols provided
   by gRPC Swift.
4. You _may_ extend types provided by gRPC Swift at `package`, `internal`,
   `private` or `fileprivate` level.
5. You _may_ extend types provided by gRPC Swift at `public` access level if
   doing so means that a symbol clash is impossible (such as including a type
   you own in the signature, or prefixing the method with the namespace of your
   package in much the same way that gRPC Swift will prefix new symbols).

[0]: https://semver.org
[1]: https://github.com/grpc/grpc-swift
[2]: https://github.com/grpc/grpc-swift-nio-transport
[3]: https://github.com/grpc/grpc-swift-protobuf
[4]: https://github.com/grpc/grpc-swift-extras
