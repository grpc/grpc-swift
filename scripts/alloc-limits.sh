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

# This script parses output from the SwiftNIO allocation counter framework to
# generate a list of per-test limits for total_allocations.
#
# Input is like:
#   ...
#   test_embedded_server_unary_1k_rpcs_1_small_request.total_allocated_bytes: 5992858
#   test_embedded_server_unary_1k_rpcs_1_small_request.total_allocations: 63000
#   test_embedded_server_unary_1k_rpcs_1_small_request.remaining_allocations: 0
#   DEBUG: [["total_allocated_bytes": 5992858, "total_allocations": ...
#
# Output:
#   MAX_ALLOCS_ALLOWED_embedded_server_unary_1k_rpcs_1_small_request=64000

grep 'test_.*\.total_allocations: ' \
  | sed 's/^test_/MAX_ALLOCS_ALLOWED_/' \
  | sed 's/.total_allocations://' \
  | awk '{ print "              " $1 ": " ((int($2 / 1000) + 1) * 1000) }' \
  | sort
