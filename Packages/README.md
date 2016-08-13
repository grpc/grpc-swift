# Swift gRPC Packages

This directory contains the Swift gRPC API and related components
in the form of buildable Swift packages.

Follow these steps to build and run them on Linux.

## Prerequisites

These instructions are for running in the Docker container manager,
but can be directly used on any Ubuntu 14.04 image.

## Start Docker

Start a docker instance with the following command:

`docker run -i -t --privileged=true ubuntu:14.04 /bin/bash`

## Install Dependencies

    # update package list
    apt-get update
    # install download tools
    apt-get install git wget -y
    # install grpc build dependencies
    apt-get install build-essential autoconf libtool -y 
    # install swift dependencies
    apt-get install clang libicu-dev libedit-dev python-dev libxml2-dev -y

## Install Swift

    # go to /root
    cd 
    # download and unpack swift
    wget https://swift.org/builds/swift-3.0-preview-3/ubuntu1404/swift-3.0-PREVIEW-3/swift-3.0-PREVIEW-3-ubuntu14.04.tar.gz
    tar xzf swift-3.0-PREVIEW-3-ubuntu14.04.tar.gz

## Add Swift to your path

	# add swift to your path by adding this to your .bashrc
	export SWIFT=swift-3.0-PREVIEW-3-ubuntu14.04
	export PATH=/root/$SWIFT/usr/bin:$PATH

	# Then run this to update your path
	source ~/.bashrc

## Configure git

	git config --global user.email <your email address>
	git config --global user.name "<your name>"

## Fetch and build grpc
	git clone https://github.com/timburks/grpc 
	cd grpc
	git submodule update --init
	git checkout swift
	make
	make install

## Build the gRPC packages
	cd src/swift/Packages/
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
	
