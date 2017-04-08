#!/bin/sh
printf "\033c"
read -p "Would you like to download and install swift-protobuf / grpc [y/N]" CONDITION;
if [ "$CONDITION" == "y" ] ; then
    read -p "Use last known stable branch - 0.9.24 ? or  latest master ? [S/l]  " CONDITION;
    if [ "$CONDITION" == "l" ] ; then
        git clone https://github.com/apple/swift-protobuf.git
        cd swift-protobuf
        make install
        cd ..
        git clone https://github.com/grpc/grpc.git
        cd grpc
        git submodule update --init
        make install
    else
        git clone -b 0.9.24 https://github.com/apple/swift-protobuf.git
        cd swift-protobuf
        make install
        cd ..
        git clone https://github.com/grpc/grpc.git
        cd grpc
        git submodule update --init
        make install
    fi
fi


