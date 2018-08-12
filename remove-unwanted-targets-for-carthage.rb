require 'xcodeproj'
project_path = ARGV[0]
project = Xcodeproj::Project.open(project_path)

carthage_targets = ["BoringSSL", "CgRPC", "SwiftGRPC", "SwiftProtobuf"]
targets_to_remove = []

project.targets.each do |target|
  if !carthage_targets.include?(target.name)
    targets_to_remove << target
  else
    puts target.name
    target.build_configurations.each do |config|
      config.build_settings["IPHONEOS_DEPLOYMENT_TARGET"] = "9.0"
    end
  end
end

targets_to_remove.each do |target|
  target.remove_from_project
end

project.save
