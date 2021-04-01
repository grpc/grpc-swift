#!/bin/bash

# Copyright 2021, gRPC Authors All rights reserved.
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

# This script was adapted from SwiftNIO's 'run-nio-alloc-counter-tests.sh'
# script. The license for the original work is reproduced below. See NOTICES.txt
# for more.

##===----------------------------------------------------------------------===##
##
## This source file is part of the SwiftNIO open source project
##
## Copyright (c) 2019 Apple Inc. and the SwiftNIO project authors
## Licensed under Apache License v2.0
##
## See LICENSE.txt for license information
## See CONTRIBUTORS.txt for the list of SwiftNIO project authors
##
## SPDX-License-Identifier: Apache-2.0
##
##===----------------------------------------------------------------------===##

set -eu
here="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
tmp_dir="/tmp"

while getopts "t:" opt; do
  case "$opt" in
    t)
      tmp_dir="$OPTARG"
      ;;
    *)
      exit 1
      ;;
  esac
done

nio_checkout=$(mktemp -d "$tmp_dir/.swift-nio_XXXXXX")
(
cd "$nio_checkout"
git clone --depth 1 https://github.com/apple/swift-nio
)

shift $((OPTIND-1))

tests_to_run=("$here"/test_*.swift)

if [[ $# -gt 0 ]]; then
  tests_to_run=("$@")
fi

# We symlink in a bunch of components from the GRPCPerformanceTests target to
# avoid duplicating a bunch of code.
"$nio_checkout/swift-nio/IntegrationTests/allocation-counter-tests-framework/run-allocation-counter.sh" \
  -p "$here/../../.." \
  -m GRPC \
  -t "$tmp_dir" \
  -s "$here/shared/Common.swift" \
  -s "$here/shared/Benchmark.swift" \
  -s "$here/shared/echo.pb.swift" \
  -s "$here/shared/echo.grpc.swift" \
  -s "$here/shared/MinimalEchoProvider.swift" \
  -s "$here/shared/EmbeddedServer.swift" \
  "${tests_to_run[@]}"
