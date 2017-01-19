#!/bin/sh

shopt -s globstar

SRCROOT=third_party/grpc/third_party/boringssl
DSTROOT=Sources/BoringSSL

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
