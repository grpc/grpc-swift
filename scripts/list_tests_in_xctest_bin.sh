#!/bin/bash

# Copyright 2022, gRPC Authors All rights reserved.
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

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo >&2 "USAGE"
  echo >&2 "  $0 LINUX_XCTEST_BINARY MODULE_NAME..."
  echo >&2
  echo >&2 "EXAMPLE"
  echo >&2 "  $0 ./.build/x86_64-unknown-linux-gnu/debug/somePackageTests.xctest TestModule AnotherTestModule"
  exit 1
fi

function join {
  local IFS='|'
  echo "$*"
}

function list_tests {
  local xctest=$1
  local module_pattern=$2

  # Extract the symbols and demangle them. Then filter out the test functions
  # which look like '<MODULE>.<CLASS>.test<NAME>()'. Reformat them to match
  # the output of 'swift test --list-tests': '<MODULE>.<CLASS>/test<NAME>'.
  # Finally, sort the output.
  objdump --syms "$xctest" \
    | swift demangle \
    | grep -E -o "(${module_pattern})\.[a-zA-Z0-9_]+\.test[a-zA-Z0-9_]+\(\)" \
    | sed -e 's/()//' -e 's#\.#/#2' \
    | sort --unique
}

xctest_path=$1
shift
modules=$*
module_pattern=$(join "${modules[@]}")
list_tests "$xctest_path" "$module_pattern"
