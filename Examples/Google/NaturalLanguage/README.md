# Calling the Google Cloud Natural Language API

This directory contains a very simple sample that calls the 
[Google Cloud Natural Language API](https://cloud.google.com/datastore/docs/reference/rpc/google.datastore.v1).
Calls are made directly to the Cloud Natural Language RPC interface. 
In practice, these would be wrapped in idiomatic code.

Use [RUNME](RUNME) to generate the necessary Protocol Buffer
and gRPC support code. It uses protoc and the Swift Protocol
Buffer and gRPC plugins, so please be sure these are in your
path. The plugins can be built by running `make` in the 
top-level Plugins directory.

Calls require a Google project ID and service account credentials.

To create a project ID, visit the 
[Google Cloud Console](https://cloud.google.com/console).

Service account support is provided by Google's 
[Auth Library for Swift](https://github.com/google/auth-library-swift).
After enabling the Cloud Natural Language API for your project,
create and download service account credentials. Then set the
GOOGLE_APPLICATION_CREDENTIALS environment variable to point to 
the file containing these credentials.

