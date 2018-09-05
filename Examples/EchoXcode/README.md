# Echo gRPC Sample App

The Echo Xcode project contains a Mac app that can be used to
instantiate and run local gRPC clients and servers. It depends
on the gRPC Xcode project, which requires a local build of the
gRPC Core C library. To build that, please run `make` in the
root of your gRPC distribution. Next use Xcode's "Add Files..."
command to add the SwiftGRPC.xcodeproj to your project and
then add the SwiftGRPC, CgRPC, BoringSSL, and SwiftProtobuf
libraries to the "Linked Frameworks and Libraries" build phase of "Echo".
