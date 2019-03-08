#!/bin/sh

# Copyright 2019, gRPC Authors All rights reserved.
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

# This script vendors the gRPC Core library into the
# CgRPC module in a form suitable for building with
# the Swift Package Manager.
#
# For usage, see `vendor-all.sh`.

source ./tmp/grpc/swift-vendoring.sh

TMP_DIR=./tmp
DSTROOT=../Sources
DSTASSETS=../Assets

#
# Remove previously-vendored code.
#
echo "REMOVING any previously-vendored gRPC code"
rm -rf $DSTROOT/CgRPC/src
rm -rf $DSTROOT/CgRPC/grpc
rm -rf $DSTROOT/CgRPC/third_party
rm -rf $DSTROOT/CgRPC/include/grpc

#
# Copy grpc headers and source files
#
echo "COPYING public gRPC headers"
for src in "${public_headers[@]}"
do
	dest="$DSTROOT/CgRPC/$src"
	dest_dir=$(dirname $dest)
	mkdir -pv $dest_dir
	cp $TMP_DIR/grpc/$src $dest
done

echo "COPYING private gRPC headers"
for src in "${private_headers[@]}"
do
	dest="$DSTROOT/CgRPC/$src"
	dest_dir=$(dirname $dest)
	mkdir -pv $dest_dir
	cp $TMP_DIR/grpc/$src $dest
done

echo "COPYING gRPC source files"
for src in "${source_files[@]}"
do
	dest="$DSTROOT/CgRPC/$src"
	dest_dir=$(dirname $dest)
	mkdir -pv $dest_dir
	cp $TMP_DIR/grpc/$src $dest
done

echo "COPYING additional nanopb headers"
cp $TMP_DIR/grpc/third_party/nanopb/*.h $DSTROOT/CgRPC/third_party/nanopb/

echo "ADDING additional compiler flags to nanopb/pb.h"
perl -pi -e 's/\/\* #define PB_FIELD_16BIT 1 \*\//#define PB_FIELD_16BIT 1/' $DSTROOT/CgRPC/third_party/nanopb/pb.h

echo "ADDING additional compiler flags to tsi/ssl_transport_security.cc"
perl -pi -e 's/#define TSI_OPENSSL_ALPN_SUPPORT 1/#define TSI_OPENSSL_ALPN_SUPPORT 0/' $DSTROOT/CgRPC/src/core/tsi/ssl_transport_security.cc

echo "DISABLING ARES"
perl -pi -e 's/#define GRPC_ARES 1/#define GRPC_ARES 0/' $DSTROOT/CgRPC/include/grpc/impl/codegen/port_platform.h

echo "COPYING roots.pem"
cp $TMP_DIR/grpc/etc/roots.pem $DSTASSETS/roots.pem
