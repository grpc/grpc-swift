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

# This script contains part of SwiftNIO's test_functions.sh script. The license
# for the original work is reproduced below. See NOTICES.txt for more.

##===----------------------------------------------------------------------===##
##
## This source file is part of the SwiftNIO open source project
##
## Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
## Licensed under Apache License v2.0
##
## See LICENSE.txt for license information
## See CONTRIBUTORS.txt for the list of SwiftNIO project authors
##
## SPDX-License-Identifier: Apache-2.0
##
##===----------------------------------------------------------------------===##

function fail() {
  echo >&2 "FAILURE: $*"
  false
}

function assert_less_than() {
  if [[ ! "$1" -lt "$2" ]]; then
    fail "assertion '$1' < '$2' failed"
  fi
}

function assert_less_than_or_equal() {
  if [[ ! "$1" -le "$2" ]]; then
    fail "assertion '$1' <= '$2' failed"
  fi
}

function assert_greater_than() {
  if [[ ! "$1" -gt "$2" ]]; then
    fail "assertion '$1' > '$2' failed"
  fi
}

g_has_previously_infoed=false

function info() {
  if ! $g_has_previously_infoed; then
    echo || true # echo an extra newline so it looks better
    g_has_previously_infoed=true
  fi
  echo "info: $*" || true
}

function warn() {
  echo "warning: $*"
}
