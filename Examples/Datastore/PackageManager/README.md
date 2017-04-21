# Calling the Google Cloud Datastore API

This directory contains a very simple sample that calls the 
[Google Cloud Datastore API](https://cloud.google.com/datastore/docs/reference/rpc/google.datastore.v1).
Calls are made directly to the Datastore RPC interface. 
In practice, these would be wrapped in idiomatic code.

Use [RUNME](RUNME) to generate the necessary Protocol Buffer
and gRPC support code.

Calls require a Google project ID and an OAuth token.
Both should be specified in [Sources/main.swift](Sources/main.swift).

To create a project ID, visit the 
[Google Cloud Console](https://cloud.google.com/console).

One easy way to get an OAuth token is to use the 
[Instance Metadata Service](https://cloud.google.com/compute/docs/storing-retrieving-metadata)
that is available in Google cloud instances, such as 
[Google Compute Engine](https://cloud.google.com/compute/)
or 
[Google Cloud Shell](https://cloud.google.com/shell/docs/).
This allows you to get a short-lived service token with curl:

    curl \
	  http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token \
	  -H Metadata-Flavor:Google

That will return something like the following:

	{"access_token":"OAUTH ACCESS TOKEN","expires_in":1799,"token_type":"Bearer"}
    

Put the string matching OAUTH ACCESS TOKEN in the `authToken` variable in 
[Sources/main.swift](Sources/main.swift).
Please note that you must run the `curl` command from within a Google cloud instance.
Once you have the OAuth token, you can use it from anywhere until it expires.

CAUTION: Please take care to not share your OAuth token. 
It provides access to all of your Google services.
