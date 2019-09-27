#!/bin/bash -e

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

# See: Makefile
BUILD_OUTPUT=./.build/debug

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NO_COLOR='\033[0m'

info() {
  printf "${BLUE}$1${NO_COLOR}\n"
}

success() {
  printf "${GREEN}$1${NO_COLOR}\n"
}

setup_environment() {
  echo -en 'travis_fold:start:script.environment\\r'
  export PATH=$HOME/local/bin:$PATH
  export LD_LIBRARY_PATH=$HOME/local/lib
  echo -en 'travis_fold:end:script.environment\\r'
}

make_all() {
  echo -en 'travis_fold:start:make.all\\r'
  info "Running make all"
  make all
  success "make all succeeded"
  echo -en 'travis_fold:end:make.all\\r'
}

make_test() {
  echo -en 'travis_fold:start:make.test\\r'
  info "Running Swift tests"
  make test
  success "Swift tests passed"
  echo -en 'travis_fold:end:make.test\\r'
}

make_test_plugin() {
  echo -en 'travis_fold:start:make.test_plugin\\r'
  info "Validating protoc plugins on the Echo service"
  make test-plugin
  success "Validated protoc plugins on the Echo service"
  echo -en 'travis_fold:end:make.test_plugin\\r'
}

make_check_linuxmain() {
  echo -en 'travis_fold:start:make.test_generate_linuxmain\\r'
  info "Validating LinuxMain is up-to-date"
  if [ "$TRAVIS_OS_NAME" = "osx" ]; then
    make test-generate-linuxmain
    success "LinuxMain is up-to-date"
  else
    info "Not running on macOS, skipping LinuxMain validation"
  fi
  echo -en 'travis_fold:end:make.test_generate_linuxmain\\r'
}

make_project() {
  echo -en 'travis_fold:start:make.project\\r'
  info "Validating .xcodeproj can be generated"
  if [ "$TRAVIS_OS_NAME" = "osx" ]; then
    make project
    info ".xcodeproj was successfully generated"
  else
    info "Not running on macOS, skipping .xcodeproj generation"
  fi
  echo -en 'travis_fold:end:make.project\\r'
}

run_interop_tests() {
  echo -en 'travis_fold:start:test.interop_tests\\r'
  make interop-test-runner
  INTEROP_TEST_SERVER_PORT=8080

  # interop_server should be on $PATH
  info "Starting C++ interop server on port $INTEROP_TEST_SERVER_PORT"
  "$HOME"/local/bin/interop_server -port "$INTEROP_TEST_SERVER_PORT" &
  INTEROP_SERVER_PID=$!
  success "C++ interop server started, pid=$INTEROP_SERVER_PID"

  # Names of the tests we should run:
  TESTS=(
    empty_unary
    large_unary
    client_streaming
    server_streaming
    ping_pong
    empty_stream
    custom_metadata
    status_code_and_message
    special_status_message
    unimplemented_method
    unimplemented_service
    cancel_after_begin
    cancel_after_first_response
    timeout_on_sleeping_server
  )

  # Run the tests; logs are written to stderr, capture them per-test.
  for test in "${TESTS[@]}"; do
    info "Running $test"
    $BUILD_OUTPUT/GRPCInteroperabilityTests run_test \
      "localhost" \
      "$INTEROP_TEST_SERVER_PORT" \
      "$test" \
        2> "interop.$test.log"
    success "PASSED $test"
  done

  success "Interop tests PASSED"
  info "Stopping C++ interop server"
  kill "$INTEROP_SERVER_PID"
  success "Stopped C++ interop server"
  echo -en 'travis_fold:end:test.interop_tests\\r'
}

run_interop_reconnect_test() {
  echo -en 'travis_fold:start:test.interop_reconnect\\r'
  make interop-backoff-test-runner
  INTEROP_TEST_SERVER_CONTROL_PORT=8081
  INTEROP_TEST_SERVER_RETRY_PORT=8082

  # reconnect_interop_server should be on $PATH
  info "Starting C++ reconnect interop server:"
  info " - control port: ${INTEROP_TEST_SERVER_CONTROL_PORT}"
  info " - retry port: ${INTEROP_TEST_SERVER_RETRY_PORT}"
  "$HOME"/local/bin/reconnect_interop_server \
    -control_port "$INTEROP_TEST_SERVER_CONTROL_PORT" \
    -retry_port "$INTEROP_TEST_SERVER_RETRY_PORT" &
  INTEROP_RECONNECT_SERVER_PID=$!
  success "C++ reconnect interop server started, pid=$INTEROP_RECONNECT_SERVER_PID"

  info "Running connection backoff interop test"
  # Run the test; logs are written to stderr, redirect them to a file.
  ${BUILD_OUTPUT}/GRPCConnectionBackoffInteropTest \
    ${INTEROP_TEST_SERVER_CONTROL_PORT} \
    ${INTEROP_TEST_SERVER_RETRY_PORT} \
      2> "interop.connection_backoff.log"
  success "connection backoff interop test PASSED"

  info "Stopping C++ reconnect interop server"
  kill "$INTEROP_RECONNECT_SERVER_PID"
  success "Stopped C++ reconnect interop server"
  echo -en 'travis_fold:end:test.interop_reconnect\\r'
}

main() {
  setup_environment

  # If we're running interop tests don't bother with the other stuff.
  if [ "$RUN_INTEROP_TESTS" = "true" ]; then
    run_interop_tests
    run_interop_reconnect_test
  else
    make_all
    make_check_linuxmain
    make_test
    make_test_plugin
    make_project
  fi
}

# Run the thing!
main
