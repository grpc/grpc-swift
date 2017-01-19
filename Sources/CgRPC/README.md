# CgRPC source files

This directory contains source code for CgRPC, the C support library for gRPC.
It includes a custom "shim" (in the shim directory) and vendored code from 
the gRPC Core library.

| README.md   | this file                                                              |
| shim        | custom code created to simplify the Swift gRPC interface to gRPC Core. |
| include     | headers for the CgRPC module                                           |
| grpc        | headers for gRPC core (internal)                                       |
| src         | source code for gRPC core (internal)                                   |
| third_party | third-party source code used by gRPC core (internal)                   |
