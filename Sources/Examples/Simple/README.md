# Simple, a Swift gRPC Sample App

This sample illustrates the use of low-level Swift gRPC APIs in
clients and servers. Please note that typical gRPC applications
would not use these APIs but would use code generated using the
Swift gRPC plugin for protoc.

The Simple app is built with the Swift Package Manager and is
a command-line tool that can be run as a client or server. 
Pass the "server" argument to run it as a server and "client"
to run it as a client.

It requires a local build of the gRPC Core C library. To build 
that, please run "make" in the root of your gRPC distribution.