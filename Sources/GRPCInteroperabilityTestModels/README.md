# gRPC Interoperability Test Protos

This module contains the generated models for the gRPC interoperability tests
and the script used to generate them.

The tests require that some methods and services are left unimplemented, this
requires manual edits after code generation. These instructions are emitted to
`stdout` at the end of the `generate.sh` script.

* `generate.sh`: generates models from interoperability test protobufs.
* `src`: source of protobufs.
* `Generated`: output directory for generated models.
