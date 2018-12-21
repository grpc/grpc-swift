# Swift gRPC Samples

Follow these steps to build and run Swift gRPC on Linux.

## Prerequisites

These instructions are for running in the Docker container manager,
but can be directly used on any Ubuntu 16.04 image.

## Start Docker

Start a docker instance with the following command:

`docker run -i -t --privileged=true ubuntu:16.04 /bin/bash`

## Install Dependencies

    # update package list
    apt-get update
    # install download tools
    apt-get install -y git wget
    # install a few useful utilities
    apt-get install -y vim sudo unzip
    # install swift dependencies
    apt-get install -y clang libicu-dev libedit-dev python-dev libxml2-dev
    # install networking dependencies
    apt-get install -y libcurl4-openssl-dev libssl-dev libnghttp2-dev

## Install Swift

    # go to /root
    cd /root
    # download and unpack swift
    wget https://swift.org/builds/swift-4.2.1-release/ubuntu1604/swift-4.2.1-RELEASE/swift-4.2.1-RELEASE-ubuntu16.04.tar.gz
    tar xzf swift-4.2.1-RELEASE-ubuntu16.04.tar.gz
    ln -s swift-4.2.1-RELEASE-ubuntu16.04 swift

## Add Swift to your path

    # add swift to your path by adding this to your .bashrc
    export PATH=/root/swift/usr/bin:$PATH

    # Then run this to update your path
    source ~/.bashrc

## Configure git

    git config --global user.email <your email address>
    git config --global user.name "<your name>"

## Get and build Swift gRPC

    cd /root
    git clone https://github.com/grpc/grpc-swift.git
    cd grpc-swift
    make

## Run the test client and server

    # start the server
    .build/debug/Echo serve &
    # run the client to test each Echo API
    .build/debug/Echo get
    .build/debug/Echo expand
    .build/debug/Echo collect
    .build/debug/Echo update

## To test the plugin

    # download and install protoc
    cd /root
    wget https://github.com/google/protobuf/releases/download/v3.5.1/protoc-3.5.1-linux-x86_64.zip
    unzip protoc-3.5.1-linux-x86_64.zip -d /usr

    # build and test the plugin
    cd /root/grpc-swift
    make test-plugin
