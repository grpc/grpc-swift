# Echo, a gRPC Sample App

This directory contains a simple echo server and client
that demonstrates all four gRPC API styles (Unary, Server 
Streaming, Client Streaming, and Bidirectional Streaming).
It includes Swift and Go implementations to verify 
interoperability.

The [Xcode](Xcode) directory contains a Mac app and 
[PackageManager](PackageManager) contains a command-line tool
that can be built with the Swift Package Manager. Both contain
a Swift client and server, and both are hard-coded to use port
8081 for insecure connections and port 8443 for secure connections.

The [Go](Go) directory contains a Go client and server. The Go server
listens on port 8080 and the Go client connects to this by
default but can be pointed at other servers using the "-a" 
command-line option.

