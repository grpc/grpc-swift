#!/bin/sh
printf "\033c"
read -p "Would you like to download and install swift-protobuf / grpc [y/N]" CONDITION;
if [ "$CONDITION" == "y" ] ; then
    git clone https://github.com/apple/swift-protobuf.git
    cd swift-protobuf
    make install
    cd ..
    git clone https://github.com/grpc/grpc.git
    cd grpc
    git submodule update --init
    make install
fi


