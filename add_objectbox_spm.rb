require 'xcodeproj'

project = Xcodeproj::Project.open('MiniClone.xcodeproj')
target = project.targets.find { |t| t.name == 'MiniClone' }

# Check if ObjectBox is already added
existing = project.root_object.package_references.find { |r| 
  r.respond_to?(:repositoryURL) && r.repositoryURL.to_s.include?('objectbox-swift')
}
if existing
  puts "ObjectBox already added."
else
  puts "Adding ObjectBox Swift SPM package..."
  
  package_ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  package_ref.repositoryURL = 'https://github.com/objectbox/objectbox-swift-spm.git'
  package_ref.requirement = { 'kind' => 'upToNextMajorVersion', 'minimumVersion' => '4.0.0' }
  project.root_object.package_references << package_ref

  pkg_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  pkg_dep.product_name = 'ObjectBox'
  pkg_dep.package = package_ref
  target.package_product_dependencies << pkg_dep

  project.save
  puts "Done."
end
