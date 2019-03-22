require 'xcodeproj'
project_path = ARGV[0]
project = Xcodeproj::Project.open(project_path)

# Fix indentation settings.
project.main_group.uses_tabs = '0'
project.main_group.tab_width = '2'
project.main_group.indent_width = '2'

# Set the `CURRENT_PROJECT_VERSION` variable for each config to ensure
# that the generated frameworks pass App Store validation (#291).
project.build_configurations.each do |config|
  config.build_settings["CURRENT_PROJECT_VERSION"] = "1.0"
end

# Ensure that the CgRPC framework is built as a proper framework.
cgrpc_target = project.targets.select { |target| target.name == "CgRPC" }[0]

cgrpc_target.build_configurations.each do |config|
  config.build_settings["DEFINES_MODULE"] = "YES"
end

cgrpc_ref = project.files.select { |project_file| project_file.display_name == "cgrpc.h" }[0]
cgrpc_header = cgrpc_target.headers_build_phase.add_file_reference(cgrpc_ref)
cgrpc_header.settings = { 'ATTRIBUTES' => ['Public'] }

# Set each target's iOS deployment target to 9.0
project.targets.each do |target|
  target.build_configurations.each do |config|
    config.build_settings["IPHONEOS_DEPLOYMENT_TARGET"] = "9.0"
    if config.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] then
      config.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "io.grpc." + config.build_settings["PRODUCT_BUNDLE_IDENTIFIER"]
    end
  end
end

project.save
