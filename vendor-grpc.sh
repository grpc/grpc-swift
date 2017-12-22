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

#
# Read the list of files to vendor from the gRPC project.
#
# The file that is included here is a generated file.
# To generate it, copy swift-vendoring.sh.template from
# the grpc-swift directory to grpc/templates and then
# run tools/buildgen/generate_projects.sh in the grpc
# directory.
#
source third_party/grpc/swift-vendoring.sh 

#
# Remove previously-vendored code.
#
echo "REMOVING any previously-vendored gRPC code"
rm -rf Sources/CgRPC/src
rm -rf Sources/CgRPC/grpc
rm -rf Sources/CgRPC/third_party
rm -rf Sources/CgRPC/include/grpc

#
# Copy grpc headers and source files
#
echo "COPYING public gRPC headers"
for src in "${public_headers[@]}"
do
	dest="Sources/CgRPC/$src"
	dest_dir=$(dirname $dest)
	mkdir -pv $dest_dir
	cp third_party/grpc/$src $dest
done

echo "COPYING private grpc headers"
for src in "${private_headers[@]}"
do
	dest="Sources/CgRPC/$src"
	dest_dir=$(dirname $dest)
	mkdir -pv $dest_dir
	cp third_party/grpc/$src $dest
done

echo "COPYING grpc source files"
for src in "${source_files[@]}"
do
	dest="Sources/CgRPC/$src"
	dest_dir=$(dirname $dest)
	mkdir -pv $dest_dir
	cp third_party/grpc/$src $dest
done

echo "COPYING additional nanopb headers"
cp third_party/grpc/third_party/nanopb/*.h Sources/CgRPC/third_party/nanopb/

echo "DISABLING ARES"
perl -pi -e 's/#define GRPC_ARES 1/#define GRPC_ARES 0/' Sources/CgRPC/include/grpc/impl/codegen/port_platform.h

echo "COPYING roots.pem"
cp third_party/grpc/etc/roots.pem Assets/roots.pem
