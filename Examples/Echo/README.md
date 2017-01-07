# Echo, a gRPC Sample App

This directory contains a simple echo server and client
that demonstrates all four gRPC API styles (Unary, Server 
Streaming, Client Streaming, and Bidirectional Streaming) 
and to verify interoperability of Swift and Go gRPC clients
and servers.

The [Go](Go) directory contains a Go client and server. The server
listens on localhost:8080 and the client connects to this by
default but can be pointed at other servers using the "-a" 
command-line option.

The [Swift](Swift) directory contains a Mac app and a command-line tool
that can be built with the Swift Package Manager. Both contain
a Swift client and server. 

