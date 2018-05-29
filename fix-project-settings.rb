require 'xcodeproj'
project_path = './SwiftGRPC.xcodeproj'
project = Xcodeproj::Project.open(project_path)

project.main_group.uses_tabs = '0'
project.main_group.tab_width = '2'
project.main_group.indent_width = '2'

cgrpc = project.targets.select { |t| t.name == 'CgRPC' }.first
cgrpc.build_configurations.each do |config|
  config.build_settings['CLANG_CXX_LANGUAGE_STANDARD'] = 'c++0x'
  config.build_settings['OTHER_CFLAGS'] = '-DPB_FIELD_16BIT=1'
end

project.save
