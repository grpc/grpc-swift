# Copyright 2015, Google Inc.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#
#     * Redistributions of source code must retain the above copyright
# notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above
# copyright notice, this list of conditions and the following disclaimer
# in the documentation and/or other materials provided with the
# distribution.
#     * Neither the name of Google Inc. nor the names of its
# contributors may be used to endorse or promote products derived from
# this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

Pod::Spec.new do |s|
  s.name = 'SwiftGRPC'
  s.version = '0.3.3'
  s.license  = 'New BSD'
  s.summary = 'Swift gRPC code generator plugin and runtime library'
  s.homepage = 'http://www.grpc.io'
  s.authors  = { 'The gRPC contributors' => 'grpc-packages@google.com' }
  s.source = { :git => 'https://github.com/grpc/grpc-swift.git', :tag => s.version }

  s.requires_arc = true
  #s.ios.deployment_target = '8.0'
  #s.osx.deployment_target = '10.9'
  #s.tvos.deployment_target = '9.0'
  #s.watchos.deployment_target = '2.0'

  s.source_files = 'Sources/SwiftGRPC/*.swift', 'Sources/SwiftGRPC/**/*.swift', 'Sources/CgRPC/shim/*.[ch]'
  s.public_header_files = 'Sources/CgRPC/shim/cgrpc.h'

  s.dependency 'gRPC-Core', '~> 1.9.1'
  s.dependency 'BoringSSL', '~> 9.1'
  s.dependency 'SwiftProtobuf', '~> 1.0.2'
end
