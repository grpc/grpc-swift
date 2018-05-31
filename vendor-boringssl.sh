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
# This script creates a vendored copy of BoringSSL that is
# suitable for building with the Swift Package Manager.
#
# Usage: 
#   1. Clone github.com/grpc/grpc into the third_party directory.
#   2. Get gRPC submodules by running "git submodule update --init"
#      inside the gRPC directory.
#   3. Run this script in the grpc-swift directory. It will place 
#      a local copy of the BoringSSL sources in Sources/BoringSSL.
#      Any prior contents of Sources/BoringSSL will be deleted.
#

SRCROOT=third_party/grpc/third_party/boringssl
DSTROOT=Sources/BoringSSL

echo "REMOVING any previously-vendored BoringSSL code"
rm -rf $DSTROOT/include
rm -rf $DSTROOT/ssl
rm -rf $DSTROOT/crypto
rm -rf $DSTROOT/err_data.c

PATTERNS=(
'include/openssl/*.h'
'ssl/*.h'
'ssl/*.cc'
'crypto/*.h'
'crypto/*.c'
'crypto/*/*.h'
'crypto/*/*.c'
'crypto/*/*/*.h'
'crypto/*/*/*.c'
'third_party/fiat/*.h'
'third_party/fiat/*.c'
)

EXCLUDES=(
'*_test.*'
'test_*.*'
'test'
'example_*.c'
)

for pattern in "${PATTERNS[@]}" 
do
  for i in $SRCROOT/$pattern; do
    path=${i#$SRCROOT}
    dest="$DSTROOT$path"
    dest_dir=$(dirname $dest)
    mkdir -p $dest_dir
    cp $SRCROOT/$path $dest
  done
done

echo "COPYING err_data.c from gRPC project"
cp ./third_party/grpc/src/boringssl/err_data.c $DSTROOT

for exclude in "${EXCLUDES[@]}" 
do
  echo "EXCLUDING $exclude"
  find $DSTROOT -d -name "$exclude" -exec rm -rf {} \;
done

echo "GENERATING err_data.c"
go run $SRCROOT/crypto/err/err_data_generate.go > $DSTROOT/crypto/err/err_data.c

echo "DELETING crypto/fipsmodule/bcm.c"
rm -f $DSTROOT/crypto/fipsmodule/bcm.c

#
# edit the BoringSSL headers to disable dependency on assembly language helpers.
#
perl -pi -e '$_ .= qq(\n#define OPENSSL_NO_ASM\n) if /#define OPENSSL_HEADER_BASE_H/' Sources/BoringSSL/include/openssl/base.h
