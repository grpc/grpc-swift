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

set -eou pipefail

log() { printf -- "** %s\n" "$*" >&2; }
error() { printf -- "** ERROR: %s\n" "$*" >&2; }
fatal() { error "$@"; exit 1; }

# Clones v1 into the given directory and applies a number of patches to rename
# the package from 'grpc-swift' to 'grpc-swift-v1' and 'protoc-gen-grpc-swift'
# to 'protoc-gen-grpc-swift-v1'.
function checkout_v1 {
  # The directory to clone grpc-swift into.
  grpc_checkout_dir="$(realpath "$1")"
  # The path of the checkout.
  grpc_checkout_path="${grpc_checkout_dir}/grpc-swift-v1"

  # Clone the repo.
  log "Cloning grpc-swift to ${grpc_checkout_path}"
  git clone \
    --quiet \
    https://github.com/grpc/grpc-swift.git \
    "${grpc_checkout_path}"

  # Get the latest version of 1.x.y.
  local -r version=$(git -C "${grpc_checkout_path}" tag --list | grep '1.\([0-9]\+\).\([0-9]\+\)$' | sort -V | tail -n 1)

  log "Checking out $version"
  git -C "${grpc_checkout_path}" checkout --quiet "$version"

  # Remove the git bits.
  log "Removing ${grpc_checkout_path}/.git"
  rm -rf "${grpc_checkout_path}/.git"

  # Update the manifest to rename the package and the protoc plugin.
  package_manifest="${grpc_checkout_path}/Package.swift"
  log "Updating ${package_manifest}"
  sed -i '' \
    -e 's/let grpcPackageName = "grpc-swift"/let grpcPackageName = "grpc-swift-v1"/g' \
    -e 's/protoc-gen-grpc-swift/protoc-gen-grpc-swift-v1/g' \
    "${package_manifest}"

  # Update all references to protoc-gen-grpc-swift.
  log "Updating references to protoc-gen-grpc-swift"
  find \
    "${grpc_checkout_path}/Sources" \
    "${grpc_checkout_path}/Tests" \
    "${grpc_checkout_path}/Plugins" \
    -type f \
    -name '*.swift' \
    -exec sed -i '' 's/protoc-gen-grpc-swift/protoc-gen-grpc-swift-v1/g' {} +

  # Update the path of the protoc plugin so it aligns with the target name.
  log "Updating directory name for protoc-gen-grpc-swift-v1"
  mv "${grpc_checkout_path}/Sources/protoc-gen-grpc-swift" "${grpc_checkout_path}/Sources/protoc-gen-grpc-swift-v1"

  log "Cloned and patched v1 to: ${grpc_checkout_path}"
}


# Recursively finds '*.grpc.swift' files in the given directory and renames them
# to '*grpc.v1.swift'.
function rename_generated_grpc_code {
  local directory=$1

  find "$directory" -type f -name "*.grpc.swift" \
    -exec bash -c 'mv "$0" "${0%.grpc.swift}.grpc.v1.swift"' {} \;
}

# Applies a number of textual replacements to migrate a service implementation
# on the given file.
function patch_service_code {
  local filename=$1

  sed -E -i '' \
    -e 's/import GRPC/import GRPCCore/g' \
    -e 's/GRPCAsyncServerCallContext/ServerContext/g' \
    -e 's/: ([A-Za-z_][A-Za-z0-9_]*)AsyncProvider/: \1.SimpleServiceProtocol/g' \
    -e 's/GRPCAsyncResponseStreamWriter/RPCWriter/g' \
    -e 's/GRPCAsyncRequestStream<([A-Za-z_][A-Za-z0-9_]*)>/RPCAsyncSequence<\1, any Error>/g' \
    -e 's/responseStream.send/responseStream.write/g' \
    -e 's/responseStream:/response responseStream:/g' \
    -e 's/requestStream:/request requestStream:/g' \
    "$filename"
}

function usage {
  echo "Usage:"
  echo "  $0 clone-v1 DIRECTORY"
  echo "  $0 rename-generated-code DIRECTORY"
  echo "  $0 patch-service FILE"
  exit 1
}

if [[ $# -lt 2 ]]; then
  usage
fi

subcommand="$1"
argument="$2"

case "$subcommand" in
  "clone-v1")
    checkout_v1 "$argument"
    ;;
  "rename-generated-code")
    rename_generated_grpc_code "$argument"
    ;;
  "patch-service")
    patch_service_code "$argument"
    ;;
  *)
    usage
    ;;
esac
