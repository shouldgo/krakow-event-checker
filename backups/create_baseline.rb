#!/usr/bin/env ruby

# create_baseline.rb - Create baseline test outputs for refactoring validation
#
# This script runs the current version of event_checker.rb with predefined inputs
# and saves the outputs for comparison during refactoring.
#
# Usage: ruby create_baseline.rb

require 'date'
require 'fileutils'
require 'tempfile'

class BaselineCreator
  def initialize
    @baseline_dir = "test_baselines"
    @timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    
    puts "🧪 Creating Baseline Test Data"
    puts "=" * 40
    
    # Create baseline directory
    FileUtils.mkdir_p(@baseline_dir) unless Dir.exist?(@baseline_dir)
  end
  
  def create_all_baselines
    puts "📁 Baseline directory: #{@baseline_dir}"
    
    # Test Case 1: Small date range (2 days)
    create_baseline(
      name: "small_range",
      description: "2-day range test",
      start_date: Date.today,
      end_date: Date.today + 1
    )
    
    # Test Case 2: Medium date range (1 week)
    create_baseline(
      name: "medium_range", 
      description: "1-week range test",
      start_date: Date.today,
      end_date: Date.today + 6
    )
    
    # Test Case 3: Past events (for archive testing)
    create_baseline(
      name: "past_events",
      description: "Past events test", 
      start_date: Date.today - 3,
      end_date: Date.today - 1
    )
    
    puts "✅ All baseline tests completed!"
    puts "📋 Results saved in: #{@baseline_dir}"
  end
  
  private
  
  def create_baseline(name:, description:, start_date:, end_date:)
    puts "\n🔬 Creating baseline: #{name} (#{description})"
    puts "   Date range: #{start_date} to #{end_date}"
    
    # Create test-specific directory
    test_dir = File.join(@baseline_dir, "#{name}_#{@timestamp}")
    FileUtils.mkdir_p(test_dir)
    
    # Create input file for automated input
    input_file = File.join(test_dir, "input.txt")
    File.write(input_file, "#{start_date.strftime('%Y-%m-%d')}\n#{end_date.strftime('%Y-%m-%d')}\n")
    
    # Backup existing output files
    backup_existing_files(test_dir)
    
    # Run event checker with captured input
    output_file = File.join(test_dir, "execution_log.txt")
    cmd = "cd #{Dir.pwd} && ruby event_checker.rb < #{input_file} > #{output_file} 2>&1"
    
    puts "   🏃 Running: ruby event_checker.rb"
    system(cmd)
    
    # Capture output files
    capture_output_files(test_dir)
    
    # Create test summary
    create_test_summary(test_dir, name, description, start_date, end_date)
    
    puts "   ✅ Baseline saved: #{test_dir}"
  end
  
  def backup_existing_files(test_dir)
    files_to_backup = ['upcoming.md', 'ongoing.md', 'archive.md']
    
    files_to_backup.each do |file|
      if File.exist?(file)
        backup_path = File.join(test_dir, "before_#{file}")
        FileUtils.cp(file, backup_path)
      end
    end
  end
  
  def capture_output_files(test_dir)
    files_to_capture = ['upcoming.md', 'ongoing.md', 'archive.md']
    
    files_to_capture.each do |file|
      if File.exist?(file)
        output_path = File.join(test_dir, "after_#{file}")
        FileUtils.cp(file, output_path)
      end
    end
  end
  
  def create_test_summary(test_dir, name, description, start_date, end_date)
    summary_file = File.join(test_dir, "test_summary.md")
    
    content = <<~SUMMARY
      # Baseline Test Summary: #{name}
      
      **Description**: #{description}
      **Date Range**: #{start_date} to #{end_date}
      **Created**: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}
      **Ruby Version**: #{RUBY_VERSION}
      
      ## Test Scenario
      - Start Date: #{start_date.strftime('%Y-%m-%d')}
      - End Date: #{end_date.strftime('%Y-%m-%d')}
      - Duration: #{(end_date - start_date).to_i + 1} days
      
      ## Files Generated
      #{Dir.entries(test_dir).select { |f| f.end_with?('.md', '.txt') }.sort.map { |f| "- #{f}" }.join("\n")}
      
      ## Usage
      This baseline can be used to validate refactoring changes by:
      1. Running the same test scenario with refactored code
      2. Comparing output files for differences
      3. Ensuring functionality is preserved
      
      ## Validation Command
      ```bash
      # Run the same test scenario
      echo "#{start_date.strftime('%Y-%m-%d')}\\n#{end_date.strftime('%Y-%m-%d')}" | ruby event_checker.rb
      
      # Compare outputs
      diff after_upcoming.md upcoming.md
      diff after_ongoing.md ongoing.md  
      diff after_archive.md archive.md
      ```
    SUMMARY
    
    File.write(summary_file, content)
  end
end

# Main execution
if __FILE__ == $0
  begin
    creator = BaselineCreator.new
    creator.create_all_baselines
    
    puts "\n🎯 Baseline creation completed successfully!"
    puts "💡 Use these baselines to validate refactoring changes"
    
  rescue Interrupt
    puts "\n❌ Baseline creation cancelled by user"
    exit 1
  rescue => e
    puts "\n❌ Error creating baselines: #{e.message}"
    puts "🐛 #{e.backtrace.join("\n   ")}" if ENV['DEBUG']
    exit 1
  end
end