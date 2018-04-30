# Calling the Google Cloud Natural Language API

This directory contains a very simple sample that calls the 
[Google Cloud Natural Language API](https://cloud.google.com/datastore/docs/reference/rpc/google.datastore.v1).
Calls are made directly to the Cloud Natural Language RPC interface. 
In practice, these would be wrapped in idiomatic code.

1. Use [RUNME](RUNME) to generate the necessary Protocol Buffer
and gRPC support code. It uses protoc and the Swift Protocol
Buffer and gRPC plugins, so please be sure these are in your
path. The plugins can be built by running `make` in the 
top-level grpc-swift directory.

2. Run `pod install` to install the SwiftGRPC pod and its dependencies.

3. Open NaturalLanguage.xcworkspace and set GOOGLE_API_KEY in the application delegate.

4. Run the app.

## Prerequisites

This sample requires a Google Cloud Platform account and an API key
for the Cloud Natural Language service. 
Visit [https://cloud.google.com](cloud.google.com) for details.
