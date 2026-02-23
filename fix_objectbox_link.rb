require 'xcodeproj'

project = Xcodeproj::Project.open('MiniClone.xcodeproj')
target = project.targets.find { |t| t.name == 'MiniClone' }

# Fix the product name: should be 'ObjectBox.xcframework' not 'ObjectBox'
ob_dep = target.package_product_dependencies.find { |d| d.product_name == 'ObjectBox' }
if ob_dep
  ob_dep.product_name = 'ObjectBox.xcframework'
  project.save
  puts "Fixed: productName updated to 'ObjectBox.xcframework'"
else
  # try to find already-correct one
  ob_dep2 = target.package_product_dependencies.find { |d| d.product_name == 'ObjectBox.xcframework' }
  puts ob_dep2 ? "Already correct: ObjectBox.xcframework" : "ERROR: could not find ObjectBox dependency"
end
