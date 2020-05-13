Pod::Spec.new do |s|

    s.name = 'gRPC-Swift'
    s.module_name = 'GRPC'
    s.version = '1.0.0-alpha.12'
    s.license = { :type => 'Apache 2.0', :file => 'LICENSE' }
    s.summary = 'Swift gRPC code generator plugin and runtime library'
    s.homepage = 'https://www.grpc.io'
    s.authors  = { 'The gRPC contributors' => 'grpc-packages@google.com' }

    s.source = { :git => 'https://github.com/grpc/grpc-swift.git', :tag => s.version }

    s.swift_version = '5.0'
    s.ios.deployment_target = '10.0'
    s.osx.deployment_target = '10.12'
    s.tvos.deployment_target = '10.0'
    s.source_files = 'Sources/GRPC/**/*.{swift,c,h}'

    s.dependency 'Logging', '1.2.0'
    s.dependency 'SwiftNIO', '2.15.0'
    s.dependency 'SwiftNIOHTTP2', '1.11.0'
    s.dependency 'SwiftNIOSSL', '2.7.1'
    s.dependency 'SwiftNIOTransportServices', '1.3.0'
    s.dependency 'SwiftProtobuf', '1.8.0'
    s.dependency 'CGRPCZlib', s.version.to_s

end