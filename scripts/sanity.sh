#!/bin/bash

# Copyright 2020, gRPC Authors All rights reserved.
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

set -eu

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

function run_logged() {
  local message=$1
  local command=$2

  log=$(mktemp)

  printf '==> %s ... ' "$message"

  if $command > "$log" 2>&1; then
    printf "\033[0;32mOK\033[0m\n"
  else
    errors=$(( errors + 1))
    printf "\033[0;31mFAILED\033[0m\n"
    echo "=== Captured output:"
    cat "$log"
    echo "==="
  fi
}

function check_license_headers() {
  run_logged "Checking license headers" "$HERE/license-check.sh"
}

function check_formatting() {
  run_logged "Checking formatting" "$HERE/format.sh lint"
}

errors=0
check_license_headers
check_formatting
exit $errors
