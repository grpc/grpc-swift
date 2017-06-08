# Calling the Google Cloud Datastore API

This directory contains a very simple sample that calls the 
[Google Cloud Datastore API](https://cloud.google.com/datastore/docs/reference/rpc/google.datastore.v1).
Calls are made directly to the Datastore RPC interface. 
In practice, these would be wrapped in idiomatic code.

Use [RUNME](RUNME) to generate the necessary Protocol Buffer
and gRPC support code. It uses protoc and the Swift Protocol
Buffer and gRPC plugins, so please be sure these are in your
path. The plugins can be built by running `make` in the 
top-level Plugins directory.

Calls require a Google project ID and an OAuth token.

To create a project ID, visit the 
[Google Cloud Console](https://cloud.google.com/console).
Then edit [Sources/main.swift](Sources/main.swift) to 
replace "YOUR PROJECT ID" with your project ID.

OAuth tokens are obtained using Google's 
[Auth Library for Swift](https://github.com/google/auth-library-swift).
On OS X, this package uses a locally-installed browser and
a temporary web server to take a user through an OAuth signin flow.
On Linux, it gets an OAuth token from the
[Instance Metadata Service](https://cloud.google.com/compute/docs/storing-retrieving-metadata)
that is available in Google Cloud instances, such as 
[Google Compute Engine](https://cloud.google.com/compute/)
or 
[Google Cloud Shell](https://cloud.google.com/shell/docs/).