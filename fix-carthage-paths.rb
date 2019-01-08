require 'xcodeproj'

project_path = ARGV[0]
project = Xcodeproj::Project.open(project_path)

dependenciesGroup = project["Dependencies"]
if !dependenciesGroup.nil?
    puts dependenciesGroup.name
end

dependenciesGroup.recursive_children_groups.each do |child|
    if !Dir.exists?(child.real_path)
        path = child.path

        stringArray = path.split(".build/checkouts/").last.split("/")
        repoNameInXcodeproj = stringArray[0]
        
        if !repoNameInXcodeproj.nil? and repoNameInXcodeproj.include? ".git-"
            
            repoName = repoNameInXcodeproj.split(".git-").first
            
            projectDir = ENV["PWD"]
            spmDirPath = Dir.glob("#{projectDir}/.build/checkouts/#{repoName}**").first
            xcodeprojDirPath = "#{projectDir}/.build/checkouts/#{repoNameInXcodeproj}"

            if !spmDirPath.eql? xcodeprojDirPath
                # Rename directory created by SPM to the name that Xcodeproj file already had
                FileUtils.mv spmDirPath, xcodeprojDirPath
            end
        end
    end
end
