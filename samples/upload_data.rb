#!/usr/bin/env ruby

require '../lib/buzzdata'

if ARGV.size != 3
  puts "Usage: ./upload_data.rb dataset filename 'Change notes...'"
  puts "Example: ./upload_data.rb eviltrout/kittens-born-by-month kittens_born.csv 'Added more kittens'"
  exit(0)
end

buzzdata = Buzzdata.new

dataset_name, filename, release_notes = *ARGV

# Upload a file to a dataset
print "Uploading #{filename}..."
upload = buzzdata.upload(dataset_name, File.new(filename), release_notes)
puts "Done!"