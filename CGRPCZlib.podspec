# Copyright 2020, gRPC Authors. All rights reserved.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#   http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

Pod::Spec.new do |s|
    s.name = 'CGRPCZlib'
    s.module_name = 'CGRPCZlib'
    s.version = '1.0.0-alpha.11'
    s.license     = { :type => 'Apache 2.0', :file => 'LICENSE' }
  
    s.summary = 'Swift gRPC code generator plugin and runtime library'
    s.homepage = 'https://www.grpc.io'
    s.authors  = { 'The gRPC contributors' => 'grpc-packages@google.com' }
    s.source = { :git => 'https://github.com/grpc/grpc-swift.git', :tag => s.version }
  
    s.swift_version = '5.0'

    s.ios.deployment_target = '10.0'
    s.osx.deployment_target = '10.12'
    s.tvos.deployment_target = '10.0'
  
    s.source_files = 'Sources/CGRPCZlib/**/*.{swift,c,h}'

  end