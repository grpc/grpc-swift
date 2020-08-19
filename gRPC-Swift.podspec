Pod::Spec.new do |s|

    s.name = 'gRPC-Swift'
    s.version = '1.0.0-alpha.18'
    s.license = { :type => 'Apache 2.0', :file => 'LICENSE' }
    s.summary = 'Swift gRPC code generator plugin and runtime library'
    s.homepage = 'https://www.grpc.io'
    s.authors  = { 'The gRPC contributors' => 'grpc-packages@google.com' }

    s.swift_version = '5.0'
    s.ios.deployment_target = '10.0'
    s.osx.deployment_target = '10.12'
    s.tvos.deployment_target = '10.0'
    s.source = { :git => "https://github.com/grpc/grpc-swift.git", :tag => s.version }

    s.source_files = 'Sources/GRPC/**/*.{swift,c,h}'

    s.dependency 'Logging', '>= 1.4.0', '< 2'
    s.dependency 'SwiftNIO', '>= 2.19.0', '< 3'
    s.dependency 'SwiftNIOHTTP2', '>= 1.13.0', '< 2'
    s.dependency 'SwiftNIOSSL', '>= 2.8.0', '< 3'
    s.dependency 'SwiftNIOTransportServices', '>= 1.6.0', '< 2'
    s.dependency 'SwiftProtobuf', '>= 1.9.0', '< 2'
    s.dependency 'CGRPCZlib', s.version.to_s

end