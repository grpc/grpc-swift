#!/bin/sh
printf "\033c"
read -p "Would you like to download swift-protobuf / grpc [y/N]" CONDITION;
if [ "$CONDITION" == "y" ] ; then
    read -p "Use last known stable swift-protobuf - 0.9.901 ? or  latest master ? [S/l]  " CONDITION;
    if [ "$CONDITION" == "l" ] ; then
        git clone https://github.com/apple/swift-protobuf.git
    else
        git clone -b 0.9.901 https://github.com/apple/swift-protobuf.git
    fi
    git clone https://github.com/grpc/grpc.git
    cd grpc
    # this step is slow and only needed to rebuild the vendored Sources/BoringSSL code.
    #git submodule update --init
fi
