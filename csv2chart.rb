require 'csv'
require 'gruff'
require 'base64'

# Read CSV data from stdin
csv_data = ARGF.read

# Parse the CSV data
data = CSV.parse(csv_data, headers: true)

# Initialize a Gruff line graph
graph = Gruff::Line.new
graph.title = "CSV Column Data Graph"

# Extract all columns and add them to the graph
data.headers.each do |header|
  column_data = data[header].map(&:to_f) # Convert values to floats
  graph.data(header, column_data)
end

# Save the graph to a temporary file
temp_file = "temp_graph.png"
graph.write(temp_file)

# Read the graph image and write it to stdout as base64-encoded data
image_data = File.binread(temp_file)
puts image_data

# Clean up the temporary file
File.delete(temp_file)
