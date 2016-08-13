# Swift gRPC API

This repository contains an experimental Swift gRPC API.

Currently not intended for production use, it provides low-level
Swift wrappers for the C gRPC API that can be used to build
higher-level structures supporting streaming and nonstreaming
gRPC APIs. 

The current version contains NO protocol buffer support (yet).

Code is provided for both gRPC clients and servers,
and it can be built either with Xcode or the Swift Package Manager.
The Xcode build is demonstrated with [Sessions](Examples/Sessions), 
a sample Mac app that can be used to create and run multiple
concurrent servers and clients. 
Swift Package Manager builds are demonstrated on Linux using 
the instructions in the [Packages](Packages) directory.



