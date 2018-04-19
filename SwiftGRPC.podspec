# Copyright 2018, gRPC Authors. All rights reserved.
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
  s.name = 'SwiftGRPC'
  s.version = '0.4.2'
  s.license     = { :type => 'Apache License, Version 2.0',
                    :text => <<-LICENSE
                      Copyright 2018, gRPC Authors. All rights reserved.
                      Licensed under the Apache License, Version 2.0 (the "License");
                      you may not use this file except in compliance with the License.
                      You may obtain a copy of the License at
                        http://www.apache.org/licenses/LICENSE-2.0
                      Unless required by applicable law or agreed to in writing, software
                      distributed under the License is distributed on an "AS IS" BASIS,
                      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
                      See the License for the specific language governing permissions and
                      limitations under the License.
                    LICENSE
                  }

  s.summary = 'Swift gRPC code generator plugin and runtime library'
  s.homepage = 'https://www.grpc.io'
  s.authors  = { 'The gRPC contributors' => 'grpc-packages@google.com' }
  s.source = { :git => 'https://github.com/grpc/grpc-swift.git', :tag => s.version }

  s.requires_arc = true
  s.ios.deployment_target = '8.0'
  s.osx.deployment_target = '10.10'

  s.source_files = 'Sources/SwiftGRPC/*.swift', 'Sources/SwiftGRPC/**/*.swift', 'Sources/CgRPC/shim/*.[ch]'
  s.public_header_files = 'Sources/CgRPC/shim/cgrpc.h'

  s.dependency 'gRPC-Core', '~> 1.11.0'
  s.dependency 'BoringSSL', '~> 10.0'
  s.dependency 'SwiftProtobuf', '~> 1.0.3'
end
