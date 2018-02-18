# Swift gRPC in Docker

Swift gRPC works great within Docker.  
Follow these steps to build and run Swift gRPC in the Docker container 
from [swiftdocker](https://github.com/swiftdocker/docker-swift).

## Prerequisites

[Docker for Mac](https://docs.docker.com/docker-for-mac/).

## Fetch the Docker image

Run this command on your local system:

`docker pull swiftdocker/swift`

## Start Docker

Start a docker instance with the swiftdocker image:

`docker run -it --name swiftgrpc swiftdocker/swift:latest /bin/bash`

## Install Dependencies

    # update package list
    apt-get update
    # install a few missing pieces
    apt-get install libz-dev unzip

## Configure git (optional)

    git config --global user.email <your email address>
    git config --global user.name "<your name>"

## Get grpc-swift

    cd
    git clone https://github.com/grpc/grpc-swift

## Run the grpc-swift unit tests

    cd grpc-swift
    make test

## Build the Echo sample

    cd
    cd grpc-swift/Examples/Echo/Swift/SwiftPM
    make

## Run the test client and server 

    # start the server
    .build/debug/Echo serve &
    # run the client to test each Echo API
    .build/debug/Echo get
    .build/debug/Echo expand
    .build/debug/Echo collect
    .build/debug/Echo update
	
## Test the Swift gRPC plugin

    # install protoc
    cd
    curl -O -L https://github.com/google/protobuf/releases/download/v3.5.1/protoc-3.5.1-linux-x86_64.zip
    unzip protoc-3.5.1-linux-x86_64.zip -d /usr
    # build the Swift gRPC plugin
    cd
    cd grpc-swift/Plugin
    make
    # set environment variables to allow protoc and the plugin to run 
    export PATH=.:$PATH
    # test the plugin by regenerating code for a sample .proto service
    make test


