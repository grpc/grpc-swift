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

# This script was adapted from SwiftNIO's test_01_allocation_counts.sh. The
# license for the original work is reproduced below. See NOTICES.txt for more.

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

set -eu
here="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
tmp="/tmp"

source "$here/test-utils.sh"

all_tests=()
for file in "$here/tests/"test_*.swift; do
  # Extract the "TESTNAME" from "test_TESTNAME.swift"
  test_name=$(basename "$file")
  test_name=${test_name#test_*}
  test_name=${test_name%*.swift}
  all_tests+=( "$test_name" )
done

# Run all the tests.
"$here/tests/run-allocation-counter-tests.sh" -t "$tmp" | tee "$tmp/output"

# Dump some output from each, check for allocations.
for test in "${all_tests[@]}"; do
  while read -r test_case; do
    test_case=${test_case#test_*}
    total_allocations=$(grep "^test_$test_case.total_allocations:" "$tmp/output" | cut -d: -f2 | sed 's/ //g')
    not_freed_allocations=$(grep "^test_$test_case.remaining_allocations:" "$tmp/output" | cut -d: -f2 | sed 's/ //g')
    max_allowed_env_name="MAX_ALLOCS_ALLOWED_$test_case"

    info "$test_case: allocations not freed: $not_freed_allocations"
    info "$test_case: total number of mallocs: $total_allocations"

    assert_less_than "$not_freed_allocations" 5     # allow some slack
    assert_greater_than "$not_freed_allocations" -5 # allow some slack
    if [[ -z "${!max_allowed_env_name+x}" ]]; then
      if [[ -z "${!max_allowed_env_name+x}" ]]; then
        warn "no reference number of allocations set (set to \$$max_allowed_env_name)"
        warn "to set current number:"
        warn "    export $max_allowed_env_name=$total_allocations"
      fi
    else
      max_allowed=${!max_allowed_env_name}
      assert_less_than_or_equal "$total_allocations" "$max_allowed"
      assert_greater_than "$total_allocations" "$(( max_allowed - 1000))"
    fi
  done < <(grep "^test_$test[^\W]*.total_allocations:" "$tmp/output" | cut -d: -f1 | cut -d. -f1 | sort | uniq)
done
