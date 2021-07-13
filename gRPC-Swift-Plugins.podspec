Pod::Spec.new do |s|

    s.name = 'gRPC-Swift-Plugins'
    s.version = '1.3.0'
    s.license = { :type => 'Apache 2.0', :file => 'LICENSE' }
    s.summary = 'Swift gRPC code generator plugin binaries'
    s.homepage = 'https://www.grpc.io'
    s.authors  = { 'The gRPC contributors' => 'grpc-packages@google.com' }

    s.swift_version = '5.2'
    s.ios.deployment_target = '10.0'
    s.osx.deployment_target = '10.12'
    s.tvos.deployment_target = '10.0'
    s.watchos.deployment_target = '6.0'
    s.source = { :http => "https://github.com/grpc/grpc-swift/releases/download/#{s.version}/protoc-grpc-swift-plugins-#{s.version}.zip"}

    s.preserve_paths = '*'
    s.dependency 'gRPC-Swift', s.version.to_s

end