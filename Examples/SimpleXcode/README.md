# Swift gRPC Sample App

This sample illustrates the use of low-level Swift gRPC APIs in
clients and servers. Please note that typical gRPC applications
would not use these APIs but would use code generated using the
Swift gRPC plugin for protoc.

The Simple Xcode project contains a Mac app that can be used to 
instantiate and run local gRPC clients and servers. It depends
on the gRPC Xcode project, which requires a local build of the
gRPC Core C library. To build that, please run "make" in the
root of your gRPC distribution. Next use Xcode's "Add Files..."
command to add the SwiftGRPC.xcodeproj to your project and
then add the gRPC, CgRPC, and BoringSSL libraries to the target
dependencies of "Simple".

When running the app, use the "New" menu option to create new
gRPC sessions. Configure each session using the host and port
fields and the client/server selector, and then press "start"
to begin serving or calling the server that you've specified.

See the "Document" class for client and server implementations.
