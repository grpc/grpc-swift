#!/bin/bash

# Copyright 2019, gRPC Authors All rights reserved.
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

# This script checks the copyright headers in source *.swift source files and
# exits if they do not match the expected header. The year, or year range in
# headers is replaced with 'YEARS' for comparison.

# Copyright header text and SHA for *.swift files
read -r -d '' COPYRIGHT_HEADER_SWIFT << 'EOF'
/*
 * Copyright YEARS, gRPC Authors All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
EOF
SWIFT_SHA=$(echo "$COPYRIGHT_HEADER_SWIFT" | shasum | awk '{print $1}')

# Copyright header text and SHA for *.grpc.swift files
read -r -d '' COPYRIGHT_HEADER_SWIFT_GRPC << 'EOF'
// Copyright YEARS, gRPC Authors All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
EOF
SWIFT_GRPC_SHA=$(echo "$COPYRIGHT_HEADER_SWIFT_GRPC" | shasum | awk '{print $1}')

# Copyright header text and SHA for *.pb.swift files
read -r -d '' COPYRIGHT_HEADER_SWIFT_PB << 'EOF'
// Copyright YEARS gRPC authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
EOF
SWIFT_GRPC_PB=$(echo "$COPYRIGHT_HEADER_SWIFT_PB" | shasum | awk '{print $1}')

replace_years() {
  sed -e 's/201[56789]-20[12][0-9]/YEARS/' -e 's/201[56789]/YEARS/'
}

# Checks the Copyright headers for *.swift files in this repository against the
# expected headers.
#
# Prints the names of all files with invalid or missing headers and exits with
# a non-zero status code.
check_copyright_headers() {
  # Exceptions:
  # - {echo,annotations,language_service,http}.pb.swift: Google is the author of
  #   the corresponding .protos, so the generated header has Google as the
  #   author.
  # - LinuxMain.swift, XCTestManifests.swift: Both of these files are generated
  #   by SwiftPM and do not have headers.
  while read -r filename; do
    case $filename in
      # The .grpc.swift and .pb.swift files have additional generated headers with
      # warnings that they have been generated and should not be edited.
      # Package.swift is preceeded by a "swift-tools-version" line.
      *.grpc.swift)
        expected_sha="$SWIFT_GRPC_SHA"
        drop_first=8
        expected_lines=13
        ;;
      *.pb.swift)
        expected_sha="$SWIFT_GRPC_PB"
        drop_first=9
        expected_lines=13
        ;;
      */Package.swift)
        expected_sha="$SWIFT_SHA"
        drop_first=1
        expected_lines=15
        ;;
      *)
        expected_sha="$SWIFT_SHA"
        drop_first=0
        expected_lines=15
        ;;
    esac

    actual_sha=$(head -n "$((drop_first + expected_lines))" "$filename" \
      | tail -n "$expected_lines" \
      | sed -e 's/201[56789]-20[12][0-9]/YEARS/' -e 's/20[12][0-9]/YEARS/' \
      | shasum \
      | awk '{print $1}')

    if [ "$actual_sha" != "$expected_sha" ]; then
      printf "\033[0;31mMissing or invalid copyright headers in '%s'\033[0m\n" "$filename"
      errors=$(( errors + 1 ))
    fi

  done < <(find . -name '*.swift' \
    ! -name 'echo.pb.swift' \
    ! -name 'annotations.pb.swift' \
    ! -name 'language_service.pb.swift' \
    ! -name 'http.pb.swift' \
    ! -name 'LinuxMain.swift' \
    ! -name 'XCTestManifests.swift' \
    ! -path './.build/*')
}

errors=0
check_copyright_headers

if [[ "$errors" == 0 ]]; then
  echo "License headers: OK"
else
  echo "License headers: found $errors issue(s)."
fi

exit $errors
