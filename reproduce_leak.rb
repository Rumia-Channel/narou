require_relative "lib/narou"
require_relative "lib/novelconverter"
require_relative "lib/inventory"
require "fileutils"

# Mock $stdout2 if needed (usually set in CLI)
$stdout2 ||= $stdout

# Ensure Inventory is initialized
Inventory.load("test_init")

# Simulate a large object in Inventory
# We don't need actual data, just the object identity
puts "Initial Inventory cache size: #{Inventory.class_variable_get(:@@cache).size}"

obj1 = NovelConverter.section_convert_cache
puts "Obj1 ID: #{obj1.object_id}"

# Clear Inventory
Inventory.clear
puts "Inventory cleared."
# Access @@cache safely
cache_size = begin
               Inventory.class_variable_get(:@@cache).size
             rescue NameError
               0
             end
puts "Inventory cache size: #{cache_size}"

# Access again
obj2 = NovelConverter.section_convert_cache
puts "Obj2 ID: #{obj2.object_id}"

if obj1.object_id == obj2.object_id
  puts "FAIL: Object persisted in NovelConverter after Inventory clear."
else
  puts "SUCCESS: Object was reloaded/cleared."
end
