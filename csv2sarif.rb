#!/usr/bin/env ruby
require 'json'
require 'csv'

tool_name, tool_version, findings_csv = ARGV

results = []

def add_result(rule_id, level, message, uri, start_line, end_line)
  {
    "ruleId": rule_id,
    "level": level,
    "message": {
      "text": message
    },
    "locations": [
      {
        "physicalLocation": {
          "artifactLocation": {
            "uri": uri
          },
          "region": {
            "startLine": Integer(start_line),
            "endLine": Integer(end_line),
          }
        }
      }
    ]
  }
end

sarif_data = { :$schema => "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",
           :version => "2.1.0",
           :runs => [
             { tool: { driver: { name: tool_name,
                                       version: tool_version,
                                       informationUri: "https://github.com/simpsonjulian/statica",
                                       rules: [],
                                       organization: "simpsonjulian" } },
               results: [] }
           ] }

CSV.foreach(findings_csv) do |row|
  results << add_result(*row)
end

sarif_data[:runs][0][:results] = results
puts sarif_data.to_json

