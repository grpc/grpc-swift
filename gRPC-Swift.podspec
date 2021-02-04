Pod::Spec.new do |s|

    s.name = 'gRPC-Swift'
    s.module_name = 'GRPC'
    s.version = '1.0.0'
    s.license = { :type => 'Apache 2.0', :file => 'LICENSE' }
    s.summary = 'Swift gRPC code generator plugin and runtime library'
    s.homepage = 'https://www.grpc.io'
    s.authors  = { 'The gRPC contributors' => 'grpc-packages@google.com' }

    s.swift_version = '5.2'
    s.ios.deployment_target = '10.0'
    s.osx.deployment_target = '10.12'
    s.tvos.deployment_target = '10.0'
    s.watchos.deployment_target = '6.0'
    s.source = { :git => "https://github.com/grpc/grpc-swift.git", :tag => s.version }

    s.source_files = 'Sources/GRPC/**/*.{swift,c,h}'

    s.dependency 'CGRPCZlib', s.version.to_s
    s.dependency 'Logging', '>= 1.4.0', '< 2.0.0'
    s.dependency 'SwiftNIO', '>= 2.22.0', '< 3.0.0'
    s.dependency 'SwiftNIOExtras', '>= 1.4.0', '< 2.0.0'
    s.dependency 'SwiftNIOHTTP2', '>= 1.16.1', '< 2.0.0'
    s.dependency 'SwiftNIOSSL', '>= 2.8.0', '< 3.0.0'
    s.dependency 'SwiftNIOTransportServices', '>= 1.6.0', '< 2.0.0'
    s.dependency 'SwiftProtobuf', '>= 1.9.0', '< 2.0.0'

end