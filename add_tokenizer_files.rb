require 'xcodeproj'

project = Xcodeproj::Project.open('MiniClone.xcodeproj')
target = project.targets.find { |t| t.name == 'MiniClone' }

# Find groups
models_group = project.main_group.find_subpath(File.join('MiniClone', 'Models'), false)
services_group = project.main_group.find_subpath(File.join('MiniClone', 'Services'), false)

if models_group.nil? || services_group.nil?
  puts "Error: Could not find MiniClone/Models or MiniClone/Services group"
  exit 1
end

# Add CLIPTokenizer.swift to Sources
tokenizer_path = 'CLIPTokenizer.swift'
unless services_group.children.find { |c| c.path == tokenizer_path }
  file_ref = services_group.new_reference(tokenizer_path)
  target.source_build_phase.add_file_reference(file_ref, true)
  puts "Added CLIPTokenizer.swift to sources"
else
  puts "CLIPTokenizer.swift already in project"
end

# Add vocab.json to Resources
vocab_path = 'vocab.json'
unless models_group.children.find { |c| c.path == vocab_path }
  file_ref = models_group.new_reference(vocab_path)
  target.resources_build_phase.add_file_reference(file_ref, true)
  puts "Added vocab.json to resources"
else
  puts "vocab.json already in project"
end

# Add merges.txt to Resources
merges_path = 'merges.txt'
unless models_group.children.find { |c| c.path == merges_path }
  file_ref = models_group.new_reference(merges_path)
  target.resources_build_phase.add_file_reference(file_ref, true)
  puts "Added merges.txt to resources"
else
  puts "merges.txt already in project"
end

project.save
puts "Done!"
