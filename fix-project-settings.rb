require 'xcodeproj'
project_path = ARGV[0]
project = Xcodeproj::Project.open(project_path)

project.main_group.uses_tabs = '0'
project.main_group.tab_width = '2'
project.main_group.indent_width = '2'

cgrpc_target = project.targets.select { |target| target.name == "CgRPC" }[0]

cgrpc_target.build_configurations.each do |config|
  config.build_settings["DEFINES_MODULE"] = "YES"
end

cgrpc_ref = project.files.select { |project_file| project_file.display_name == "cgrpc.h" }[0]
cgrpc_header = cgrpc_target.headers_build_phase.add_file_reference(cgrpc_ref)
cgrpc_header.settings = { 'ATTRIBUTES' => ['Public'] }

project.save
