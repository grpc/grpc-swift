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

function log() { printf -- "** %s\n" "$*" >&2; }
function error() { printf -- "** ERROR: %s\n" "$*" >&2; }
function fatal() { error "$*"; exit 1; }

function usage() {
  echo >&2 "Usage:"
  echo >&2 "  $0 -[f|l]"
  echo >&2 ""
  echo >&2 "Options:"
  echo >&2 "  -f   Format source code in place (default)"
  echo >&2 "  -l   Lint check without formatting the source code"
}

format=true
lint=false
while getopts ":flh" opt; do
  case "$opt" in
    f)
      format=true
      lint=false
      ;;
    l)
      format=false
      lint=true
      ;;
    h)
      usage
      exit 1
      ;;
    \?)
      usage
      exit 1
      ;;
  esac
done

here="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
repo="$here/.."

if "$lint"; then
  swift format lint \
    --parallel --recursive --strict \
    "${repo}/Sources" \
    "${repo}/Tests" \
    "${repo}/Plugins" \
    "${repo}/Performance/Benchmarks/Benchmarks/GRPCSwiftBenchmark" \
    && SWIFT_FORMAT_RC=$? || SWIFT_FORMAT_RC=$?

  if [[ "${SWIFT_FORMAT_RC}" -ne 0 ]]; then
    fatal "Running swift format produced errors.

    To fix, run the following command:

    % $THIS_SCRIPT -f
    "
    exit "${SWIFT_FORMAT_RC}"
  fi

  log "Ran swift format lint with no errors."
elif "$format"; then
  swift format \
    --parallel --recursive --in-place \
    "${repo}/Sources" \
    "${repo}/Tests" \
    "${repo}/Plugins" \
    "${repo}/Performance/Benchmarks/Benchmarks/GRPCSwiftBenchmark" \
    && SWIFT_FORMAT_RC=$? || SWIFT_FORMAT_RC=$?

  if [[ "${SWIFT_FORMAT_RC}" -ne 0 ]]; then
    fatal "Running swift format produced errors." "${SWIFT_FORMAT_RC}"
  fi

  log "Ran swift format with no errors."
else
  fatal "No actions taken."
fi
