Pod::Spec.new do |s|
  s.name     = 'echoapi'
  s.version  = '0.0.1'
  s.license  = 'Apache 2.0'
  s.authors  = { 'Google Inc.' => 'timburks@google.com'}
  s.homepage = 'http://github.com/GoogleCloudPlatform/ios-docs-samples'
  s.source   = { :git => 'https://github.com/GoogleCloudPlatform/ios-docs-samples.git',
                 :tag => '0.0.1' }
  s.summary  = 'Echo Sample API'	  

  s.ios.deployment_target = '7.1'
  s.osx.deployment_target = '10.9'

  # Run protoc with the Objective-C and gRPC plugins to generate protocol messages and gRPC clients.
  s.dependency "!ProtoCompiler-gRPCPlugin", "~> 1.0.0-pre1.1"

  # Pods directory corresponding to this app's Podfile, relative to the location of this podspec.
  pods_root = '../Pods'

  # Path where Cocoapods downloads protoc and the gRPC plugin.
  protoc_dir = "#{pods_root}/!ProtoCompiler"
  protoc = "#{protoc_dir}/protoc"
  plugin = "#{pods_root}/!ProtoCompiler-gRPCPlugin/grpc_objective_c_plugin"
  
  # Run protoc with the Objective-C and gRPC plugins to generate protocol messages and gRPC clients.
  # You can run this command manually if you later change your protos and need to regenerate.  
  s.prepare_command = <<-CMD
    #{protoc} \
        --plugin=protoc-gen-grpc=#{plugin} \
        --objc_out=. \
        --grpc_out=. \
        -I . \
        -I #{protoc_dir} \
        *.proto
  CMD

  # The --objc_out plugin generates a pair of .pbobjc.h/.pbobjc.m files for each .proto file.
  s.subspec "Messages" do |ms|
    ms.source_files = "*.pbobjc.{h,m}"
    ms.header_mappings_dir = "."
    ms.requires_arc = false
    ms.dependency "Protobuf"
  end

  # The --objcgrpc_out plugin generates a pair of .pbrpc.h/.pbrpc.m files for each .proto file with
  # a service defined.
  s.subspec "Services" do |ss|
    ss.source_files = "*.pbrpc.{h,m}"
    ss.header_mappings_dir = "."
    ss.requires_arc = true
    ss.dependency "gRPC-ProtoRPC"
    ss.dependency "#{s.name}/Messages"
  end
  
  s.pod_target_xcconfig = {
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) GPB_USE_PROTOBUF_FRAMEWORK_IMPORTS=1',
	  'USER_HEADER_SEARCH_PATHS' => '$SRCROOT/..'
  }

end

