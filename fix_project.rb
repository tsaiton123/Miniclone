require 'xcodeproj'
project_path = 'MiniClone.xcodeproj'
unless File.exist?(project_path)
  puts "Error: Project not found at #{project_path}"
  exit 1
end

project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'MiniClone' }
unless target
  puts "Error: Target 'MiniClone' not found"
  exit 1
end

# Find or create groups
def get_or_create_group(parent, name)
  group = parent.children.find { |c| c.display_name == name && c.isa == 'PBXGroup' }
  group || parent.new_group(name)
end

mini_clone_group = project.main_group.find_subpath('MiniClone', false)
unless mini_clone_group
  puts "Error: MiniClone group not found"
  exit 1
end

models_group = get_or_create_group(mini_clone_group, 'Models')
services_group = get_or_create_group(mini_clone_group, 'Services')

# Helper to add file if not already present
def add_file(project, target, group, file_name, is_resource = false)
  file_path = File.join(group.real_path, file_name)
  
  # Check if file exists on disk
  unless File.exist?(file_path)
    puts "Warning: File #{file_path} not found on disk."
    # return
  end

  # Check if already in group
  file_ref = group.children.find { |c| c.path == file_name }
  if file_ref.nil?
    puts "Adding #{file_name} to group #{group.display_name}"
    file_ref = group.new_reference(file_name)
  else
    puts "#{file_name} already in group #{group.display_name}"
  end

  # Add to build phase if not already present
  if is_resource
    phase = target.resources_build_phase
  else
    phase = target.source_build_phase
  end

  unless phase.files_references.include?(file_ref)
    puts "Adding #{file_name} to #{is_resource ? 'Resources' : 'Sources'} build phase"
    phase.add_file_reference(file_ref, true)
  else
    puts "#{file_name} already in build phase"
  end
end

add_file(project, target, services_group, 'CLIPTokenizer.swift', false)
add_file(project, target, models_group, 'vocab.json', true)
add_file(project, target, models_group, 'merges.txt', true)

project.save
puts "Successfully updated project"
