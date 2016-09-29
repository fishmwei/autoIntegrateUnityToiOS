#实现细节
# 1 拷贝unity3D导出的工程下的 Data/Classes/Libraries 三个目录到工程xxx根目录下的 xxx/unity目录下， 并添加到工程中； 添加xxx/unity目录下的unityUtil目录文件到工程中
# 2 添加对应的frameworks
# 3 修改工程的buildSetting
# 

require 'rubygems'
require 'xcodeproj'
require 'plist'
require 'fileutils'
require 'json'
require 'optparse'
require 'ostruct'
require 'time'

$base_path = FileUtils.pwd()
$project_path = "#{$base_path}/testProj.xcodeproj"
$app_target_name = "testProj"

class OptionReader
	def self.parse(args)
		options = OpenStruct.new
		options.issimulator = false
		options.unityProjectDir = ""

		opts = OptionParser.new do |opts|
			opts.banner = "\nUsage: ruby addUnityFunc.rb -u ../unityProjectDir -p project-name -t target-name"
			opts.separator "Specific Options:"

			opts.on("-s", "--issimulator", "模拟器") do |issimulator|
				options.issimulator = true;
				puts options.issimulator
			end

			opts.on("-u", "--unityProjectDir [dir]，[required]", "unity工程目录, 是一个工程根目录的相对路径") do |unityProjectDir|
			    options.unityProjectDir = unityProjectDir
			end

			opts.on("-p", "--project-name [required]", "工程名称 格式为xxx.xcodeproj") do |project_name|
				options.project_name = project_name;
				$project_path = "#{$base_path}/#{project_name}"
			end

			opts.on("-t", "--target-name [required]", "target名称 xxx") do |target_name|
				options.target_name=target_name;
				$app_target_name = target_name
			end
		end

		opts.parse!(args)
		options
	end
end

######################################### add files #############################################
class AddFilesHandler
	def initialize(relativeUnityProjDir, project)
		@unityProjectDir = relativeUnityProjDir;
		#@unityPath = "#{$base_path}/#{relativeUnityProjDir}"
		@unityPath = relativeUnityProjDir

		xx = File.join("#{@unityPath}", "Classes");
		@project = project;
		project.targets.each do |target|
			if target.name == $app_target_name
				@target = target
				break;
			end
		end

		#remove main.m
		build_phase = @target.source_build_phase
		build_phase.files.each do |file|
			if file.file_ref.name=="main.m" then
				file.remove_from_project;
				build_phase.remove_file_reference(file)
				file.file_ref.remove_from_project
				break;
			end	
		end

		#@target.headers_build_phase.clear(); 
		@renderGroup = @project.main_group.find_subpath(File.join("#{$app_target_name}", "render"), false);
		if @renderGroup then
			clearGroup(@renderGroup);
		end

		@renderGroup = @project.main_group.find_subpath(File.join("#{$app_target_name}", "render"), true);
		@renderGroup.clear();
		@renderGroup.set_source_tree('SOURCE_ROOT');
		
	end

	def clearGroup(group)
		# todo clear resource
		groupResource = group.children.select { |obj| obj.class == Xcodeproj::Project::Object::PBXFileReference }

		group.groups.each do |subGroup|
			clearGroup(subGroup);
		end
		
		groupResource.each do |resource|
			
		end

		group.files.each do |fref|
			@target.source_build_phase.remove_file_reference(fref)
			@target.resources_build_phase.remove_file_reference(fref);
			@target.headers_build_phase.remove_file_reference(fref)
		end
		group.remove_from_project;
	end
	def addFiles
		#add reference
		referenceData
		referenceClassess
		referenceLibraries
		referenceUnityUtil
	end

	#添加Data目录， 并拷贝
	def referenceData
		dataPath = File.join("#{@unityPath}", "Data");
		puts dataPath;

		fr = @renderGroup.new_reference(dataPath);
		@target.add_resources([fr]);
	end

	def createGroup(parentGroup, groupName, groupPath)
		#puts groupPath

		thisGroup = parentGroup[groupName];
		if thisGroup 
			thisGroup.clear();
		end
		unless  thisGroup
			thisGroup = parentGroup.new_group(groupName, groupPath);
		end
		thisGroup.set_source_tree('SOURCE_ROOT');

		thisGroupFiles  = Dir::entries(groupPath);
		fileRefs = [];
		thisGroupFiles.each do |file|
			if file == "." || file == ".." then
				next
			end
			#puts file 
			fileSuffix = file[/\.[^\.]+$/];
			filePath = File.join(groupPath, file);
			#puts filePath;

			if File::directory?(filePath) then 
				createGroup(thisGroup, file, filePath);
			else
				# fileRealPath =  filePath ;
				fileRealPath = File.join("#{$base_path}", filePath);
				puts fileRealPath
				#puts fileSuffix
				if fileSuffix == '.m' || fileSuffix == '.mm' || fileSuffix == '.c' || fileSuffix == '.cpp' || fileSuffix == '.a'#add source file
					fr = thisGroup.new_reference(fileRealPath);
					if file != 'main.mm'
						fileRefs << fr;		
					end

					if file == "libiPhone-lib.a" then 
						AddFrameworksHandler.addUnityiPhoneLib(@project, fileRealPath);
					end
				elsif  fileSuffix == '.h' || fileSuffix == '.hh' 
					# fileRealPath = File.join("#{$base_path}", filePath);

					fr = thisGroup.new_reference(fileRealPath);
					# fileRefs << fr;
				elsif fileSuffix == '.pch'
					# fileRealPath = File.join("#{$base_path}", filePath);
					fr = thisGroup.new_reference(fileRealPath);
			 	else
			 		puts 'xxxx'
			 	end
			end
		end
		# puts 'add file fileRefs'
		# puts fileRefs.length
		if fileRefs.length > 0 then
			@target.add_file_references(fileRefs);
		end
	end

	def referenceClassess
		classesPath = File.join("#{@unityPath}", "Classes");
		createGroup(@renderGroup, "Classes", classesPath)
	end

	def referenceLibraries
		librariesPath = File.join("#{@unityPath}", "Libraries");
		createGroup(@renderGroup, "Libraries", librariesPath)
	end

	def referenceUnityUtil
		puts 'referenceUnityUtil  bbbbbbbbbbbbb'
		# unityPath = "#{$base_path}/#{$app_target_name}/unity/unityUtil"
		unityPath = File.join("./#{$app_target_name}/unity", "unityUtil");
		createGroup(@renderGroup, File::basename(unityPath), unityPath)
	end
end

######################################### add frameworks #############################################
class AddFrameworksHandler
	def initialize(project)
		@targetProject = project;
		@requiredFrameworks = ["CoreText", "AudioToolbox", "CFNetwork",
							   "CoreGraphics", "CoreLocation", "CoreVideo", 
							   "Foundation", "MediaPlayer", "OpenAL", "OpenGLES",
							   "QuartzCore", "SystemConfiguration", "UIKit", "CoreMedia"];
		@optionalFrameworks = ["iAd", "CoreMotion", "AVFoundation"];

	end

	def AddFrameworksHandler.exist_framework?(build_phase, name)
	  build_phase.files.each do |file|
	    return true if file.file_ref.name == "#{name}.framework"

	    return true if file.file_ref.name == name
	  end
	  false
	end

	def add_system_frameworks(project, names, optional = false)
		project.targets.each do |target|
			next unless $app_target_name == target.name

			build_phase = target.frameworks_build_phase
			framework_group = project.frameworks_group

			names.each do |name|
				next if AddFrameworksHandler.exist_framework?(build_phase, name)
				path = "System/Library/Frameworks/#{name}.framework"
				file_ref = framework_group.new_reference(path)
				file_ref.name = "#{name}.framework"
				file_ref.source_tree = 'SDKROOT'
				build_file = build_phase.add_file_reference(file_ref)
				if optional
					build_file.settings = { 'ATTRIBUTES' => ['Weak'] }
				end
			end
		end
	end

	def add_system_lib(project, names, optional = false) 
		project.targets.each do |target|
			next unless $app_target_name == target.name

			build_phase = target.frameworks_build_phase
			framework_group = project.frameworks_group

			names.each do |name|
				next if AddFrameworksHandler.exist_framework?(build_phase, name)
				path = "usr/lib/"+name
				puts path
				file_ref = framework_group.new_reference(path)
				file_ref.name = name
				file_ref.source_tree = 'SDKROOT'
				build_file = build_phase.add_file_reference(file_ref)
				if optional
					build_file.settings = { 'ATTRIBUTES' => ['Weak'] }
				end
			end
		end
	end

	def AddFrameworksHandler.addUnityiPhoneLib(project, libpath, optional=false)
		project.targets.each do |target|
			next unless $app_target_name == target.name

			build_phase = target.frameworks_build_phase
			#remove old .a
			build_phase.files.each do |file|
				if file.file_ref.name == "libiPhone-lib.a"
					file.remove_from_project;
					build_phase.remove_file_reference(file)
					file.file_ref.remove_from_project
					break
			    end
			end

			framework_group = project.frameworks_group

			if false == exist_framework?(build_phase, "libiPhone-lib.a") then
				path = libpath
				file_ref = framework_group.new_reference(path)
				file_ref.name = "libiPhone-lib.a"
				# file_ref.source_tree = 'SDKROOT'
				build_file = build_phase.add_file_reference(file_ref)
				if optional
					build_file.settings = { 'ATTRIBUTES' => ['Weak'] }
				end
			end
		end
	end

	def addFrameworks
		add_system_frameworks(@targetProject, @requiredFrameworks);
		add_system_frameworks(@targetProject, @optionalFrameworks, true);
		add_system_lib(@targetProject, ["libiconv.2.tbd"]);
	end

end

######################################### build setting #############################################

class ModifyBuildSetting
	def initialize(project, issimulator)
		@project = project;
		@issimulator = issimulator;
		project.targets.each do |target|
			if target.name == $app_target_name
				@target = target
				break;
			end
		end
	end

	def appendFlag(originalFlag, flags)
		if !originalFlag || originalFlag.empty? then
			originalFlag = [];
		elsif "#{originalFlag.class}"=="String" # 只有一个值的时候 todo
			originalFlag = [originalFlag];
		else
			# puts 'length'
			# puts originalFlag.length
		end

		flags.each do |flag|
			originalFlag << flag;
		end
		originalFlag
	end

	def changBuildSetting(key, appendValue)
		@target.build_configurations.each do |configuration|
			originalValue = configuration.build_settings[key];
			originalValue = appendFlag(originalValue, appendValue);
			configuration.build_settings[key] = originalValue;
		end
	end

	def resetBuildSetting(key, value)
		@target.build_configurations.each do |configuration|
			configuration.build_settings[key] = value;
		end
	end

	def add_other_linker_flag
		flags = ["-weak_framework", "CoreMotion", "-weak-lSystem"];
		if @issimulator == true then  #真机需要这些值
			flags.push("-Wl,-undefined,dynamic_lookup");
		end
		changBuildSetting('OTHER_LDFLAGS', flags);
	end

	def add_search_paths(relativeUnityProjDir)
		headerPath = ["Classes", "Classes/Native", "Libraries/bdwgc/include", "Libraries/libil2cpp/include"];
		addHeaderPath = [File.join("$(SRCROOT)", relativeUnityProjDir)];
		headerPath.each do |dirpath|
			addHeaderPath << File.join("$(SRCROOT)", relativeUnityProjDir, dirpath)
		end
		changBuildSetting('HEADER_SEARCH_PATHS', addHeaderPath);

		libPath = ["Libraries"];
		addlibSearch = [File.join("$(SRCROOT)", relativeUnityProjDir)];
		libPath.each do |dirpath|
			addlibSearch << File.join("$(SRCROOT)", relativeUnityProjDir, dirpath)
		end
		changBuildSetting('LIBRARY_SEARCH_PATHS', addlibSearch);
	end

	def add_other_c_flag
		flags = ['-DINIT_SCRIPTING_BACKEND=1', '-DAPF_MAIN_ENABLE_UNITY=1']
		if @issimulator == true then
			flags << '-DTARGET_IPHONE_SIMULATOR=1'
		end
		changBuildSetting('OTHER_CFLAGS', flags);
	end

	def set_prefix_pch(pchPath)
		resetBuildSetting('GCC_PRECOMPILE_PREFIX_HEADER', 'YES');
		resetBuildSetting('GCC_PREFIX_HEADER', pchPath);
	end
	def set_c_cpp_flags
		#disable C++ Runtime Types
		resetBuildSetting('GCC_ENABLE_CPP_RTTI', 'NO');
		#set C++ Language Dialect C++11【-std=c++11】
		resetBuildSetting('CLANG_CXX_LANGUAGE_STANDARD', 'c++0x');
		#set C Language Dialect C99[-std=c99]
		resetBuildSetting('GCC_C_LANGUAGE_STANDARD', 'c99');
		#set Enable Module(C and Objective-C)
		resetBuildSetting('CLANG_ENABLE_MODULES', 'NO');
		#overriding Deprecated Objective-C Methods
		resetBuildSetting('CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS', 'YES')

		# set bitcode NO, no necessary
		# resetBuildSetting('ENABLE_BITCODE', 'NO')
	end

	def set_user_define_macro
		resetBuildSetting('GCC_THUMB_SUPPORT', 'NO');
		resetBuildSetting('GCC_USE_INDIRECT_FUNCTION_CALLS', 'NO');
		resetBuildSetting('UNITY_RUNTIME_VERSION', '5.4.1f1');
		resetBuildSetting('UNITY_SCRIPTING_BACKEND', 'il2cpp');
		
		resetBuildSetting('TARGETED_DEVICE_FAMILY', '1,2');
	end
end



class JobProcessor
	def initialize(options)
		@unityProjectDir = options.unityProjectDir;
		@issimulator = options.issimulator;
	end

	#处理操作
	def action
		# # FileUtils.cd($project_path);
		# puts FileUtils.pwd();
		
		@xcode_project = Xcodeproj::Project.open($project_path)

		#copy files from unityProjectDir
		#TODO:
		# unitySourceDir = File.join("#{$base_path}/#{$app_target_name}", "unity/");
		unitySourceDir = File.join("./#{$app_target_name}", "unity/")
		# FileUtils.cp_r(File.join(@unityProjectDir, "Data/"), File.join(unitySourceDir, "Data/"));
		FileUtils.cp_r(File.join(@unityProjectDir, "Data/"), unitySourceDir);
		FileUtils.cp_r(File.join(@unityProjectDir, "Classes/"), unitySourceDir);
		FileUtils.cp_r(File.join(@unityProjectDir, "Libraries/"), unitySourceDir);
		#Classes, Libraries

		# unitySourceDir = "#{$base_path}/#{$app_target_name}/unity"
		if true   
			puts "adding files to project"
			@addFileHandler = AddFilesHandler.new(unitySourceDir, @xcode_project);
			@addFileHandler.addFiles;
		end
		if true			
			puts "adding frameworks to project"
			frameworksHandler = AddFrameworksHandler.new(@xcode_project);
			frameworksHandler.addFrameworks();
		end

		if true 
			bs = ModifyBuildSetting.new(@xcode_project, @issimulator);
			bs.add_other_linker_flag;
			bs.add_search_paths(@unityProjectDir);
			bs.add_other_c_flag;
			pchpath = File.join('$SRCROOT', @unityProjectDir, 'Classes', 'Prefix.pch');
			bs.set_prefix_pch(pchpath);
			bs.set_c_cpp_flags;
			bs.set_user_define_macro;
		end
		puts "end ... "
		@xcode_project.save
	end
end



def main(options)
	if options.unityProjectDir.empty?
		OptionReader.parse(['-h']);
		return -1;
	end

	jobber = JobProcessor.new(options)
	jobber.action();
end


main(OptionReader.parse(ARGV))