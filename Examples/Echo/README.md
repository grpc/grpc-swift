This directory contains a simple echo server that can be used to
verify interoperability of Swift and Go gRPC servers.

The Go directory contains a Go client and server. The server
listens on localhost:8080 and the client connects to this by
default but can be pointed at other servers using the "-a" 
command-line option.

The Swift directory contains a Mac app that contains a Swift
client and server. The server starts with the app and listens
on localhost:8081. The client runs in a window and connects by
default to this port but can be pointed at other servers using
the address field in the Echo window.

When the Go server and Mac app are running on the same machine,
both clients can be used to connect to both servers.

Also, for comparison, the Objective-C directory contains an iOS
client that connects to gRPC echo servers.

