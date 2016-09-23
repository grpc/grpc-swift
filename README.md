# Swift gRPC API

This repository contains an experimental Swift gRPC API.

Not yet intended for production use, it provides low-level
Swift wrappers for the C gRPC API that can be used to build
higher-level structures supporting streaming and nonstreaming
gRPC APIs. 

Temporary protocol buffer support is provided in the QuickProto
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
(Linux builds are currently untested and were presumed broken
by the addition of Grand Central Dispatch APIs for streaming
API support; they will be fixed when threading-related 
incompatibilities between Linux and Darwin are resolved).

## Can't find something?

It was harder to get the Swift package manager to deal with 
code in outside directories than to point Xcode at them, so
you'll find the code for gRPC, CgRPC, and QuickProto in the
Sources directory associated with each package.

