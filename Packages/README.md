# Swift gRPC Packages

This directory contains the Swift gRPC API and related components
in the form of buildable Swift packages.

Follow these steps to build and run them on Linux.

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
    apt-get install -y vim sudo
    # install grpc build dependencies
    apt-get install -y build-essential autoconf libtool
    # install swift dependencies
    apt-get install -y clang libicu-dev libedit-dev python-dev libxml2-dev
    # install networking dependencies
    apt-get install -y libcurl4-openssl-dev

## Install Swift

    # go to /root
    cd
    # download and unpack swift
    wget https://swift.org/builds/swift-3.0.1-release/ubuntu1604/swift-3.0.1-RELEASE/swift-3.0.1-RELEASE-ubuntu16.04.tar.gz
    tar xzf swift-3.0.1-RELEASE-ubuntu16.04.tar.gz
    ln -s swift-3.0.1-RELEASE-ubuntu16.04 swift

## Add Swift to your path
    # add swift to your path by adding this to your .bashrc
    export PATH=/root/swift/usr/bin:$PATH

    # Then run this to update your path
    source ~/.bashrc

## Configure git

    git config --global user.email <your email address>
    git config --global user.name "<your name>"

## Fetch and build grpc
    git clone https://github.com/grpc/grpc-swift
    cd grpc-swift
    git submodule update --init
    cd third_party/grpc
    git submodule update --init
    make
    make install

## Build the gRPC packages
    cd
    cd grpc-swift/Packages
    cd CgRPC; make; cd ..
    cd gRPC; make; cd ..
    cd Server; make; make install; cd ..
    cd Client; make; make install; cd ..

It may be necessary to run `make` multiple times in the Server and Client directories.
If you see an error like the following, please retry running `make`.

    root@4d5bef530019:~/grpc/src/swift/Packages/Client# make
    swift build
    Cloning /root/grpc/src/swift/Packages/gRPC
    /usr/bin/git clone --recursive --depth 10 /root/grpc/src/swift/Packages/gRPC /root/grpc/src/swift/Packages/Client/Packages/gRPC
    warning: --depth is ignored in local clones; use file:// instead.
    Cloning into '/root/grpc/src/swift/Packages/Client/Packages/gRPC'...
    done.
    No submodule mapping found in .gitmodules for path 'Packages/CgRPC-1.0.0'
    error: Git 2.0 or higher is required. Please update git and retry.
    make: *** [all] Error 1

## Run the test client and server from the grpc/src/swift/Packages directory:
    Server/Server &
    Client/Client
