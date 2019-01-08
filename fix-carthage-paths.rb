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
        repoNameInProject = stringArray[0]
        
        if !repoNameInProject.nil? and repoNameInProject.include? ".git-"
            
            repoName = repoNameInProject.split(".git-").first
            dirPath = Dir.glob("#{localDir}/.build/checkouts/#{repoName}**").first
#            pathname = Pathname(dirPath)

            newDirPath = "#{localDir}/.build/checkouts/#{repoNameInProject}"
            p dirPath
            p newDirPath
            p repoNameInProject
            if !dirPath.eql? newDirPath
                p("rename #{dirPath} to #{newDirPath}")
                FileUtils.mv dirPath, newDirPath
            end
            
            
#            newDirName = repoName + pathname.basename.to_s.split(repoName).last
#
#            if !repoNameInProject.nil?
#                stringArray[0] = newDirName
#                relativePath = ".build/checkouts/" + stringArray.join("/")
#                p relativePath
##                child.set_path(relativePath)
#            end
        end
    end
end
#p("End of script")
#project.save
