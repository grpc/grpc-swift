#!/bin/bash
## Copyright 2025, gRPC Authors All rights reserved.
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##     http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.

set -euo pipefail

log() { printf -- "** %s\n" "$*" >&2; }

here="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
root="${here}/.."

log "Checking all imports have an access level"
if grep -r "^import " --exclude-dir="Documentation.docc" "${root}/Sources"; then
  # Matches are bad!
  exit 1
else
  exit 0
fi
