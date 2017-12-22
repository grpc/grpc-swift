#!/bin/sh
#
# Copyright 2017, gRPC Authors All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
printf "\033c"
read -p "Would you like to download swift-protobuf / grpc [y/N]" CONDITION;
if [ "$CONDITION" == "y" ] ; then
    read -p "Use last known stable swift-protobuf - 1.0.2 ? or  latest master ? [S/l]  " CONDITION;
    if [ "$CONDITION" == "l" ] ; then
        git clone https://github.com/apple/swift-protobuf.git
    else
        git clone -b 1.0.2 https://github.com/apple/swift-protobuf.git
    fi
    git clone https://github.com/grpc/grpc.git
    cd grpc
    # this step is slow and only needed to rebuild the vendored Sources/BoringSSL code.
    #git submodule update --init
fi
