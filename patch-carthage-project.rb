require 'xcodeproj'
project_path = ARGV[0]
project = Xcodeproj::Project.open(project_path)

# Remove targets that we do not want Carthage to build, and set the deployment target to 9.0.
carthage_targets = ["BoringSSL", "CgRPC", "SwiftGRPC", "SwiftProtobuf"]
targets_to_remove = project.targets.select { |target| !carthage_targets.include?(target.name) }
targets_to_remove.each do |target|
  target.remove_from_project
end

# Add a `swift package resolve` step before building `SwiftProtobuf`.

swift_protobuf_target = project.targets.select { |target| target.name == "SwiftProtobuf" }[0]
swift_protobuf_build_phases = swift_protobuf_target.build_phases

swift_protobuf_target.new_shell_script_build_phase

new_script_phase = swift_protobuf_build_phases.pop
new_script_phase.shell_script = "swift package resolve"

swift_protobuf_build_phases.unshift(new_script_phase)

project.save
