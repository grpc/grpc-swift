require 'xcodeproj'
project_path = ARGV[0]
project = Xcodeproj::Project.open(project_path)

# Remove targets that we do not want Carthage to build, and set the deployment target to 9.0.
carthage_targets = ["BoringSSL", "CgRPC", "SwiftGRPC", "SwiftProtobuf"]
targets_to_remove = project.targets.select { |target| !carthage_targets.include?(target.name) }
targets_to_remove.each do |target|
  target.remove_from_project
end
project.save

# Adding to SwiftGRPC-Package.xcscheme a script to Pre-Actions of BuildAction.
# Script will resolve SPM dependecies and will fix paths issues for SwiftGRPC-Carthage.xcodeproj before everytime before build action
schemePath = Xcodeproj::XCScheme.shared_data_dir(project_path) + "SwiftGRPC-Package.xcscheme"
scheme = Xcodeproj::XCScheme.new(schemePath)

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
buildableReference.add_attribute("BlueprintIdentifier","SwiftGRPC::SwiftGRPC")
buildableReference.add_attribute("BuildableName","SwiftGRPC.framework")
buildableReference.add_attribute("BlueprintName","SwiftGRPC")
buildableReference.add_attribute("ReferencedContainer","container:SwiftGRPC-Carthage.xcodeproj")

buildActions.unshift(preActions)

scheme.save!


