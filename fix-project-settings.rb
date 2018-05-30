require 'xcodeproj'
project_path = './SwiftGRPC.xcodeproj'
project = Xcodeproj::Project.open(project_path)

project.main_group.uses_tabs = '0'
project.main_group.tab_width = '2'
project.main_group.indent_width = '2'

project.save
