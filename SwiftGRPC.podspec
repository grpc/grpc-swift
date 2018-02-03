
Pod::Spec.new do |s|
  s.name = 'SwiftGRPC'
  s.version = '0.3.2'
  s.license  = 'Apache 2'
  s.summary = 'Swift gRPC code generator plugin and runtime library'
  s.homepage = 'http://www.grpc.io'
  s.authors  = { 'The gRPC contributors' => 'grpc-packages@google.com' }

  s.private_header_files = 'Sources/**/*.h'
  s.module_map = 'SwiftGRPC.modulemap'

  s.source = { :git => 'https://github.com/timburks/grpc-swift.git', :tag => s.version }

#  s.ios.deployment_target = '8.0'
   s.osx.deployment_target = '10.12'
#  s.tvos.deployment_target = '9.0'
#  s.watchos.deployment_target = '2.0'

  s.source_files = 'Sources/**/*.swift', 'Sources/**/*.c', 'Sources/**/*.h', 'SwiftGRPC-umbrella.h'
end
