#!/bin/sh
#
# Copyright 2016, Google Inc.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#
#     * Redistributions of source code must retain the above copyright
# notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above
# copyright notice, this list of conditions and the following disclaimer
# in the documentation and/or other materials provided with the
# distribution.
#     * Neither the name of Google Inc. nor the names of its
# contributors may be used to endorse or promote products derived from
# this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
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
