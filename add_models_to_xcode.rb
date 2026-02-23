require 'xcodeproj'

project_path = 'MiniClone.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the main app target
target = project.targets.find { |t| t.name == 'MiniClone' }
if target.nil?
  puts "Error: Could not find target 'MiniClone'"
  exit 1
end

# Find the Models group
models_group = project.main_group.find_subpath(File.join('MiniClone', 'Models'), false)
if models_group.nil?
  puts "Warning: 'MiniClone/Models' group not found in Xcode project. Creating it."
  apps_group = project.main_group.find_subpath('MiniClone', false)
  models_group = apps_group.new_group('Models', 'Models')
end

# Find the Resources build phase
resources_phase = target.resources_build_phase

# Add the models
['clip_image_s1.mlpackage', 'clip_text_s1.mlpackage'].each do |model_name|
  model_path = File.join('MiniClone', 'Models', model_name)
  
  if File.exist?(model_path)
    # Check if already in the group
    file_reference = models_group.children.find { |c| c.path == model_name }
    if file_reference.nil?
      puts "Adding #{model_name} to project navigator..."
      file_reference = models_group.new_reference(model_name)
    else
      puts "#{model_name} already in project navigator."
    end
    
    # Check if already in the build phase
    if resources_phase.files_references.include?(file_reference)
      puts "#{model_name} already in Copy Bundle Resources."
    else
      puts "Adding #{model_name} to Copy Bundle Resources..."
      resources_phase.add_file_reference(file_reference, true)
    end
  else
    puts "Error: File #{model_path} does not exist on disk."
  end
end

project.save
puts "Successfully updated project.pbxproj"
