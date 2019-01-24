require 'xcodeproj'
require 'json'

project_path = ARGV[0]
project = Xcodeproj::Project.open(project_path)

dependenciesGroup = project["Dependencies"]

#Open dependencies-state.json file
file = File.read(".build/dependencies-state.json")
json = JSON.parse(file)

dependenciesGroup.recursive_children_groups.each do |child|
    if !Dir.exists?(child.real_path)
        path = child.path

        stringArray = path.split(".build/checkouts/").last.split("/")
        repoNameInXcodeproj = stringArray[0]

        if !repoNameInXcodeproj.nil? and repoNameInXcodeproj.include? ".git-"
            repoName = repoNameInXcodeproj.split(".git-").first
            
            numberOfDependencies = json["object"]["dependencies"].count
            for i in 1..numberOfDependencies
                if json["object"]["dependencies"][i-1]["packageRef"]["name"] == repoName
                    json["object"]["dependencies"][i-1]["subpath"] = repoNameInXcodeproj
                end
            end
            
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

File.open(".build/dependencies-state.json","w") do |f|
    f.write(json.to_json)
end
