# gRPC for Swift - Public API

This document will provide an overview of the gRPC API for Swift.
It follows a standard form used by each language-platform implementation.

##Basic Functionality
###_Choose a service definition proto to use for examples_
###How is a New Stub Created?
###Simple Request-Response RPC: Client-side RPC
###Simple Request-Response RPC: Server Implementation of RPC
###Show how Client does two RPCs sequentially 
###Show how Client does two RPCs asynchronously
###Any code for handling incoming RPC on server that might need to be written
###Server Streaming RPC: Client-side code
###Server Streaming RPC: Server-side code
###How is a Server Created?

##Advanced
###RPC canceling on client side
###Code to look for and handle cancelled RPC on Server side
###Client Streaming RPC: Client-side code
###Client Streaming RPC: Server-side code
###Flow control interactions while sending & receiving messages
###Flow control and buffer pool : Control API
###Bi Directional Streaming : Client-side code
###Bi Directional Streaming : Server-side code
###Any stub deletion/cleanup code needed
