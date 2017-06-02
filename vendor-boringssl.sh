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
SRCROOT=third_party/grpc/third_party/boringssl
DSTROOT=Sources/BoringSSL

rm -rf $DSTROOT/crypto
rm -rf $DSTROOT/include
rm -rf $DSTROOT/ssl
rm -rf $DSTROOT/err_data.c


PATTERNS=(
'include/openssl/*.h'
'ssl/*.h'
'ssl/*.c'
'ssl/**/*.h'
'ssl/**/*.c'
'*.c'
'crypto/*.h'
'crypto/*.c'
'crypto/**/*.h'
'crypto/**/*.c'
'*.h'
'crypto/*.h'
'crypto/**/*.h')

EXCLUDES=(
'*_test.*'
'test_*.*'
'test')

for pattern in "${PATTERNS[@]}" 
do
  echo "PATTERN $pattern"
  for i in $SRCROOT/$pattern; do
    path=${i#$SRCROOT}
    dest="$DSTROOT/$path"
    dest_dir=$(dirname $dest)
    mkdir -p $dest_dir
    echo $SRCROOT/$path 
    echo $dest
    cp $SRCROOT/$path $dest
  done
done

cp ./third_party/grpc/src/boringssl/err_data.c $DSTROOT

for exclude in "${EXCLUDES[@]}" 
do
  echo "EXCLUDE $exclude"
  find $DSTROOT -name "$exclude" -exec rm -rf {} \;
done
