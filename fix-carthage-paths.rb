require 'xcodeproj'

project_path = ARGV[0]
project = Xcodeproj::Project.open(project_path)

dependenciesGroup = project["Dependencies"]
if !dependenciesGroup.nil?
    puts dependenciesGroup.name
end

localDir = ENV["PWD"]

dependenciesGroup.recursive_children_groups.each do |child|
    if !Dir.exists?(child.real_path)
        path = child.path

        stringArray = path.split(".build/checkouts/").last.split("/")
        string = stringArray[0]
        
        if !string.nil? and string.include? ".git-"
            repoName = string.split(".git-").first
            dirPath = Dir.glob("#{localDir}/.build/checkouts/#{repoName}**").first
            pathname = Pathname(dirPath)
            newDirName = repoName + pathname.basename.to_s.split(repoName).last

            if !string.nil?
                stringArray[0] = newDirName
                relativePath = ".build/checkouts/" + stringArray.join("/")
                p relativePath
                child.set_path(relativePath)

            end
        end
    end
end

project.save
