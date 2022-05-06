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

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# In CI we diff tests that SPM knows about with test functions extracted
# from the .xctest binary. SPM also emits build output to stdout so we
# filter it out here.
swift test --package-path="${HERE}/.." --list-tests \
  | grep -E "[a-zA-Z0_9_]+.[a-zA-Z0_9_]+.test[a-zA-Z0-9_]+" \
  | sort
