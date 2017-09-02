#!/bin/sh
#
# Copyright 2016, gRPC Authors All rights reserved.
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
# This script vendors the gRPC Core library into the
# CgRPC module in a form suitable for building with
# the Swift Package Manager.
#

source third_party/grpc/swift-vendoring.sh 

rm -rf Sources/CgRPC/src
rm -rf Sources/CgRPC/grpc
rm -rf Sources/CgRPC/third_party
rm Sources/CgRPC/include/grpc

for src in "${public_headers[@]}"
do
	dest="Sources/CgRPC/$src"
	dest_dir=$(dirname $dest)
	mkdir -pv $dest_dir
	cp third_party/grpc/$src $dest
done

mv Sources/CgRPC/include/grpc Sources/CgRPC/grpc

for src in "${source_files[@]}"
do
	dest="Sources/CgRPC/$src"
	dest_dir=$(dirname $dest)
	mkdir -pv $dest_dir
	cp third_party/grpc/$src $dest
done

for src in "${private_headers[@]}"
do
	dest="Sources/CgRPC/$src"
	dest_dir=$(dirname $dest)
	mkdir -pv $dest_dir
	cp third_party/grpc/$src $dest
done

echo "TODO:"
echo "link the grpc headers"
cd Sources/CgRPC/include; ln -s ../grpc; cd ../../..
echo "get the nanopb headers"
cp third_party/grpc/third_party/nanopb/*.h Sources/CgRPC/third_party/nanopb/
echo "#define GRPC_ARES 0 in grpc/impl/codegen/port_platform.h"
perl -pi -e 's/#define GRPC_ARES 1/#define GRPC_ARES 0/' Sources/CgRPC/grpc/impl/codegen/port_platform.h

echo "ok"


