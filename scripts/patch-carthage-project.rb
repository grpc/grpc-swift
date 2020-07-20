require 'xcodeproj'
project_path = ARGV[0]
project = Xcodeproj::Project.open(project_path)

# 1) Remove targets that we do not want Carthage to build, and set the deployment target to 10.0
carthage_targets = [
    "CGRPCZlib",
    "CNIOAtomics",
    "CNIOBoringSSL",
    "CNIOBoringSSLShims",
    "CNIODarwin",
    "CNIOHTTPParser",
    "CNIOLinux",
    "CNIOSHA1",
    # "Echo",
    # "EchoImplementation",
    # "EchoModel",
    "GRPC",
    # "GRPCConnectionBackoffInteropTest",
    # "GRPCInteroperabilityTestModels",
    # "GRPCInteroperabilityTests",
    # "GRPCInteroperabilityTestsImplementation",
    # "GRPCPerformanceTests",
    # "GRPCSampleData",
    # "GRPCTests",
    # "HelloWorldClient",
    # "HelloWorldModel",
    # "HelloWorldServer",
    "Logging",
    "NIO",
    "NIOConcurrencyHelpers",
    "NIOFoundationCompat",
    "NIOHPACK",
    "NIOHTTP1",
    "NIOHTTP2",
    "NIOSSL",
    "NIOTLS",
    "NIOTransportServices",
    # "RouteGuideClient",
    # "RouteGuideModel",
    # "RouteGuideServer",
    "SwiftProtobuf",
    # "SwiftProtobufPackageDescription",
    # "SwiftProtobufPluginLibrary",
    # "grpc-swiftPackageDescription",
    # "grpc-swiftPackageTests",
    # "protoc-gen-grpc-swift",
    # "protoc-gen-swift",
    # "swift-logPackageDescription",
    # "swift-nio-http2PackageDescription",
    # "swift-nio-sslPackageDescription",
    # "swift-nio-transport-servicesPackageDescription",
    # "swift-nioPackageDescription",
]

pm_targets = [
    "CNIOAtomics",
    "CNIOBoringSSL",
    "CNIOBoringSSLShims",
    "CNIODarwin",
    "CNIOHTTPParser",
    "CNIOLinux",
    "CNIOSHA1",
    "Logging",
    "NIO",
    "NIOConcurrencyHelpers",
    "NIOFoundationCompat",
    "NIOHPACK",
    "NIOHTTP1",
    "NIOHTTP2",
    "NIOSSL",
    "NIOTLS",
    "NIOTransportServices",
    "SwiftProtobuf",
    "SwiftProtobufPluginLibrary",
]

targets_to_remove = project.targets.select { |target| !carthage_targets.include?(target.name) }
targets_to_remove.each do |target|
  target.remove_from_project
end

# 2) Prevent linking of nghttp2 library
# project.targets.each do |target|
#   target.build_configurations.each do |conf|
#     current_ldflags = target.build_settings(conf.name)["OTHER_LDFLAGS"]
#     if current_ldflags.is_a? String
#       target.build_settings(conf.name)["OTHER_LDFLAGS"] = "" if current_ldflags.downcase().include?("nghttp2")
#     else
#       cleaned_ldflags = current_ldflags.select { |flag| !flag.downcase().include?("nghttp2") }
#       target.build_settings(conf.name)["OTHER_LDFLAGS"] = cleaned_ldflags
#     end
#   end
# end

project.save    

# 3) Add SwiftProtobuf to the build actions list
schemePath = Xcodeproj::XCScheme.shared_data_dir(project_path) + "grpc-swift-Package.xcscheme"
scheme = Xcodeproj::XCScheme.new(schemePath)

def addSubTarget(project, scheme, name)
  target = project.targets.select { |target| target.name == name }.first

  newBuildAction = Xcodeproj::XCScheme::BuildAction::Entry.new(target)
  newBuildAction.build_for_archiving = true
  newBuildAction.build_for_profiling = true
  newBuildAction.build_for_running = true
  newBuildAction.build_for_testing = true
  scheme.build_action.add_entry(newBuildAction)
end

pm_targets.each { |name| addSubTarget(project, scheme, name) }

entries_to_keep = scheme.build_action.entries.select { |x|
  x.buildable_references.select { |y| carthage_targets.include?(y.target_name) }.length() > 0 
}

scheme.build_action.entries = entries_to_keep

# 4) Add a "Pre-Actions" script to the "BuildAction" of SwiftGRPC-Package.xcscheme.
# The Pre-Actions script will resolve the SPM dependencies and fix the corresponding paths in SwiftGRPC-Carthage.xcodeproj before the BuildAction
buildActions = scheme.build_action.xml_element

preActions = REXML::Element.new("PreActions")

executionAction = REXML::Element.new("ExecutionAction", preActions)
executionAction.add_attribute("ActionType","Xcode.IDEStandardExecutionActionsCore.ExecutionActionType.ShellScriptAction")

actionContent = REXML::Element.new("ActionContent", executionAction)
actionContent.add_attribute("title", "Run Script")
scriptText = "cd ${PROJECT_DIR}; swift package resolve; ruby scripts/fix-carthage-paths.rb GRPC.xcodeproj"
actionContent.add_attribute("scriptText", scriptText)

environmentBuildable = REXML::Element.new("EnvironmentBuildable", actionContent)
buildableReference = REXML::Element.new("BuildableReference", environmentBuildable)
buildableReference.add_attribute("BuildableIdentifier","primary")
buildableReference.add_attribute("BlueprintIdentifier","grpc-swift::GRPC")
buildableReference.add_attribute("BuildableName","GRPC.framework")
buildableReference.add_attribute("BlueprintName","GRPC")
buildableReference.add_attribute("ReferencedContainer","container:GRPC.xcodeproj")

buildActions.unshift(preActions)

scheme.save!
