require 'xcodeproj'
project_path = ARGV[0]
project = Xcodeproj::Project.open(project_path)

# 1) Remove targets that we do not want Carthage to build, and set the deployment target to 9.0.
carthage_targets = ["BoringSSL", "CgRPC", "SwiftGRPC", "SwiftProtobuf"]
targets_to_remove = project.targets.select { |target| !carthage_targets.include?(target.name) }
targets_to_remove.each do |target|
  target.remove_from_project
end
project.save

# 2) Add SwiftProtobuf to the build actions list
schemePath = Xcodeproj::XCScheme.shared_data_dir(project_path) + "SwiftGRPC-Package.xcscheme"
scheme = Xcodeproj::XCScheme.new(schemePath)

target = project.targets.select { |target| target.name == "SwiftProtobuf" }.first
newBuildAction = Xcodeproj::XCScheme::BuildAction::Entry.new(target)
newBuildAction.build_for_archiving = true
newBuildAction.build_for_profiling = true
newBuildAction.build_for_running = true
newBuildAction.build_for_testing = true
scheme.build_action.add_entry(newBuildAction)

# 3) Add a "Pre-Actions" script to the "BuildAction" of SwiftGRPC-Package.xcscheme.
# The Pre-Actions script will resolve the SPM dependencies and fix the corresponding paths in SwiftGRPC-Carthage.xcodeproj before the BuildAction
buildActions = scheme.build_action.xml_element

preActions = REXML::Element.new("PreActions")

executionAction = REXML::Element.new("ExecutionAction", preActions)
executionAction.add_attribute("ActionType","Xcode.IDEStandardExecutionActionsCore.ExecutionActionType.ShellScriptAction")

actionContent = REXML::Element.new("ActionContent", executionAction)
actionContent.add_attribute("title", "Run Script")
scriptText = "cd ${PROJECT_DIR}; swift package resolve; ruby fix-carthage-paths.rb SwiftGRPC-Carthage.xcodeproj"
actionContent.add_attribute("scriptText", scriptText)

environmentBuildable = REXML::Element.new("EnvironmentBuildable", actionContent)

buildableReference = REXML::Element.new("BuildableReference", environmentBuildable)
buildableReference.add_attribute("BuildableIdentifier","primary")
buildableReference.add_attribute("BlueprintIdentifier","SwiftProtobuf::SwiftProtobuf")
buildableReference.add_attribute("BuildableName","SwiftProtobuf.framework")
buildableReference.add_attribute("BlueprintName","SwiftProtobuf")
buildableReference.add_attribute("ReferencedContainer","container:SwiftGRPC-Carthage.xcodeproj")

buildActions.unshift(preActions)

scheme.save!


