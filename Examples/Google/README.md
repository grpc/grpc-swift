# Calling the Google gRPC APIs

This directory contains samples that call selected
Google gRPC APIs. Samples are typically quite basic
and demonstrate how to directly call gRPC APIs from 
generated client support code. In practice, this code
would be wrapped with higher-level Swift code.

Each sample uses protoc and the Swift Protocol
Buffer and gRPC plugins, so please be sure these are in your
path. The plugins can be built by running `make` in the 
top-level Plugins directory.

Calls to Google APIs require a Google project ID, 
API activation, and service account credentials.

1. To create a project ID, visit the 
[Google Cloud Console](https://cloud.google.com/console).
Your selected project ID should be shown in the top bar just
to the right of the **Google Cloud Platform** label. Click
on this to change projects or create a new one.

2. To activate an API, visit the Google Cloud Console,
go to the **APIs & Services** section and use its **Library**
subsection to lookup the API and click on the **Enable**
button. If you instead see a button labeled **Manage**,
the API is already activated.

3. To create service account credentials, again visit
the Google Cloud Console, go to the **APIs & Services**
section and use the **Credentials** subsection. When you
create these credentials, you'll be prompted to download
them. Do that, and then set the `GOOGLE_APPLICATION_CREDENTIALS` 
environment variable to point to the file containing 
your credentials.

Service account support is provided by Google's 
[Auth Library for Swift](https://github.com/google/auth-library-swift).
To learn more about service accounts, please see 
[Understanding Service Accounts](https://cloud.google.com/iam/docs/understanding-service-accounts).