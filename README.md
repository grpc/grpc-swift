# Swift gRPC API

This repository contains an experimental Swift gRPC API.

Currently not intended for production use, it provides low-level
Swift wrappers for the C gRPC API that can be used to build
higher-level structures supporting streaming and nonstreaming
gRPC APIs. 

Preliminary protocol buffer support is provided in the QuickProto
library. This simple Swift library provides an API for building and
parsing protocol buffers with no generated code.

Code is provided for both gRPC clients and servers,
and it can be built either with Xcode or the Swift Package Manager.
The Xcode build is demonstrated with [Echo](Examples/Echo), 
a sample Mac app that can be used to run echo clients and
servers with streaming and nonstreaming interfaces over secure (TLS)
and insecure channels.

Other examples include [Sessions](Examples/Sessions), 
[StickyNotes](Examples/StickyNotes), and 
[Speech](Examples/Speech).

Swift Package Manager builds are demonstrated on Linux using 
the instructions in the [Packages](Packages) directory.



