require 'xcodeproj'
project_path = './SwiftGRPC-Carthage.xcodeproj'
project = Xcodeproj::Project.open(project_path)

swift_protobuf_target = project.targets.select { |target| target.name == "SwiftProtobuf" }[0]
swift_protobuf_build_phases = swift_protobuf_target.build_phases

swift_protobuf_target.new_shell_script_build_phase

new_script_phase = swift_protobuf_build_phases.pop
new_script_phase.shell_script = "swift package resolve"

swift_protobuf_build_phases.unshift(new_script_phase)

project.save
