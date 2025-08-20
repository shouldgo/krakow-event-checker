#!/usr/bin/env ruby

# full_test.rb - Comprehensive test suite for refactoring validation
#
# This script runs comprehensive tests comparing the refactored version
# against established baselines to ensure all functionality is preserved.
#
# Usage: ruby full_test.rb [baseline_directory]

require 'date'
require 'fileutils'
require 'digest'

class FullTester
  def initialize(baseline_dir = nil)
    @baseline_dir = baseline_dir || find_latest_baseline
    @test_dir = "full_test_#{Time.now.strftime("%Y%m%d_%H%M%S")}"
    
    puts "🧪 Comprehensive Refactoring Validation Test"
    puts "=" * 50
    
    if @baseline_dir && Dir.exist?(@baseline_dir)
      puts "📋 Using baseline: #{@baseline_dir}"
    else
      puts "❌ No baseline directory found!"
      puts "   Run 'ruby create_baseline.rb' first to create baselines"
      exit 1
    end
  end
  
  def run_full_test
    # Create test directory
    FileUtils.mkdir_p(@test_dir)
    
    begin
      # Find all baseline test cases
      test_cases = find_baseline_test_cases
      
      if test_cases.empty?
        puts "❌ No baseline test cases found in #{@baseline_dir}"
        exit 1
      end
      
      puts "🔍 Found #{test_cases.length} test cases to run"
      
      # Run each test case
      results = []
      test_cases.each_with_index do |test_case, index|
        puts "\n" + "="*50
        puts "🧪 Running Test Case #{index + 1}/#{test_cases.length}: #{test_case[:name]}"
        result = run_test_case(test_case)
        results << { name: test_case[:name], success: result, details: test_case }
      end
      
      # Summary
      show_test_summary(results)
      
      # Return overall success
      results.all? { |r| r[:success] }
      
    ensure
      # Clean up
      FileUtils.rm_rf(@test_dir) if Dir.exist?(@test_dir)
    end
  end
  
  private
  
  def find_latest_baseline
    baseline_dirs = Dir.glob('test_baselines/*').select { |d| Dir.exist?(d) }
    return nil if baseline_dirs.empty?
    
    # Find the most recent baseline directory
    baseline_dirs.max_by { |dir| File.mtime(dir) }
  end
  
  def find_baseline_test_cases
    return [] unless Dir.exist?(@baseline_dir)
    
    # Look for test summary files
    test_cases = []
    
    Dir.glob(File.join(@baseline_dir, "*/test_summary.md")).each do |summary_file|
      test_dir = File.dirname(summary_file)
      test_name = File.basename(test_dir).split('_').first
      
      # Parse the test summary to get test parameters
      summary_content = File.read(summary_file)
      
      start_date_match = summary_content.match(/Start Date: (\d{4}-\d{2}-\d{2})/)
      end_date_match = summary_content.match(/End Date: (\d{4}-\d{2}-\d{2})/)
      
      if start_date_match && end_date_match
        test_cases << {
          name: test_name,
          directory: test_dir,
          start_date: Date.parse(start_date_match[1]),
          end_date: Date.parse(end_date_match[1]),
          summary_file: summary_file
        }
      end
    end
    
    test_cases
  end
  
  def run_test_case(test_case)
    puts "📅 Date Range: #{test_case[:start_date]} to #{test_case[:end_date]}"
    
    # Create test case directory
    case_dir = File.join(@test_dir, test_case[:name])
    FileUtils.mkdir_p(case_dir)
    
    # Backup current state
    backup_current_state(case_dir)
    
    success = false
    
    begin
      # Run event checker with same parameters
      success = run_event_checker_case(test_case, case_dir)
      
      if success
        # Compare results with baseline
        success = compare_with_baseline(test_case, case_dir)
      end
      
    ensure
      # Restore original state
      restore_original_state(case_dir)
    end
    
    success
  end
  
  def backup_current_state(case_dir)
    files_to_backup = ['upcoming.md', 'ongoing.md', 'archive.md']
    
    files_to_backup.each do |file|
      if File.exist?(file)
        backup_path = File.join(case_dir, "backup_#{file}")
        FileUtils.cp(file, backup_path)
      end
    end
  end
  
  def restore_original_state(case_dir)
    Dir.glob(File.join(case_dir, "backup_*")).each do |backup_file|
      original_file = File.basename(backup_file).sub('backup_', '')
      if File.exist?(backup_file)
        FileUtils.cp(backup_file, original_file)
      end
    end
  end
  
  def run_event_checker_case(test_case, case_dir)
    # Create input file
    input_file = File.join(case_dir, "input.txt")
    File.write(input_file, "#{test_case[:start_date].strftime('%Y-%m-%d')}\n#{test_case[:end_date].strftime('%Y-%m-%d')}\n")
    
    # Run event checker
    output_file = File.join(case_dir, "output.txt")
    error_file = File.join(case_dir, "error.txt")
    
    # Use gtimeout if available (brew install coreutils), otherwise use plain ruby
    timeout_cmd = system("which gtimeout > /dev/null 2>&1") ? "gtimeout 300" : ""
    cmd = "cd #{Dir.pwd} && #{timeout_cmd} ruby event_checker.rb < #{input_file} > #{output_file} 2> #{error_file}"
    result = system(cmd)
    
    if result
      puts "   ✅ Execution completed"
    else
      puts "   ❌ Execution failed"
      show_execution_errors(error_file, output_file)
    end
    
    result
  end
  
  def compare_with_baseline(test_case, case_dir)
    puts "🔍 Comparing results with baseline..."
    
    comparisons = [
      compare_file('upcoming.md', test_case[:directory], case_dir),
      compare_file('ongoing.md', test_case[:directory], case_dir),
      compare_file('archive.md', test_case[:directory], case_dir)
    ]
    
    success = comparisons.all?
    
    if success
      puts "   ✅ All files match baseline"
    else
      puts "   ❌ Some files differ from baseline"
    end
    
    success
  end
  
  def compare_file(filename, baseline_dir, current_dir)
    baseline_file = File.join(baseline_dir, "after_#{filename}")
    current_file = filename
    
    # Handle case where baseline file doesn't exist
    unless File.exist?(baseline_file)
      if File.exist?(current_file)
        puts "   ⚠️  #{filename}: baseline missing, current exists (may be acceptable)"
        return true  # Don't fail for this
      else
        puts "   ✅ #{filename}: both baseline and current missing"
        return true
      end
    end
    
    # Handle case where current file doesn't exist
    unless File.exist?(current_file)
      puts "   ❌ #{filename}: baseline exists but current missing"
      return false
    end
    
    # Compare file contents
    baseline_content = File.read(baseline_file)
    current_content = File.read(current_file)
    
    # Normalize content for comparison (remove timestamps)
    baseline_normalized = normalize_content_for_comparison(baseline_content)
    current_normalized = normalize_content_for_comparison(current_content)
    
    if baseline_normalized == current_normalized
      puts "   ✅ #{filename}: matches baseline"
      return true
    else
      puts "   ❌ #{filename}: differs from baseline"
      show_content_diff(filename, baseline_normalized, current_normalized)
      return false
    end
  end
  
  def normalize_content_for_comparison(content)
    # Remove timestamps and version-specific information
    normalized = content.dup
    
    # Remove timestamp lines
    normalized.gsub!(/_Last updated: .*_\n/, "_Last updated: [TIMESTAMP]_\n")
    
    # Remove version lines (in case version changed)
    normalized.gsub!(/_Generated by Kraków Event Checker v[\d.]+_\n/, "_Generated by Kraków Event Checker [VERSION]_\n")
    
    # Normalize whitespace
    normalized.strip
  end
  
  def show_content_diff(filename, baseline, current)
    puts "      📋 Content differences in #{filename}:"
    
    baseline_lines = baseline.split("\n")
    current_lines = current.split("\n")
    
    # Show first few differences
    max_lines = [baseline_lines.length, current_lines.length].max
    diff_count = 0
    
    (0...max_lines).each do |i|
      baseline_line = baseline_lines[i] || ""
      current_line = current_lines[i] || ""
      
      if baseline_line != current_line
        puts "         Line #{i+1}:"
        puts "         - Baseline: #{baseline_line[0..80]}#{baseline_line.length > 80 ? '...' : ''}"
        puts "         + Current:  #{current_line[0..80]}#{current_line.length > 80 ? '...' : ''}"
        
        diff_count += 1
        break if diff_count >= 3  # Show only first 3 differences
      end
    end
    
    if diff_count == 0
      puts "         (No line-by-line differences found - possibly whitespace/encoding)"
    end
  end
  
  def show_execution_errors(error_file, output_file)
    if File.exist?(error_file) && File.size(error_file) > 0
      puts "      📋 Stderr:"
      puts File.read(error_file).lines.last(5).map { |line| "         #{line.strip}" }
    end
    
    if File.exist?(output_file)
      puts "      📋 Last output:"
      puts File.read(output_file).lines.last(5).map { |line| "         #{line.strip}" }
    end
  end
  
  def show_test_summary(results)
    puts "\n" + "="*50
    puts "📊 FULL TEST SUMMARY"
    puts "="*50
    
    passed = results.count { |r| r[:success] }
    total = results.length
    
    puts "✅ Passed: #{passed}/#{total}"
    puts "❌ Failed: #{total - passed}/#{total}"
    
    if total > 0
      puts "📈 Success Rate: #{(passed.to_f / total * 100).round(1)}%"
    end
    
    puts "\n📋 Test Case Details:"
    results.each do |result|
      status = result[:success] ? "✅ PASS" : "❌ FAIL"
      puts "   #{status} - #{result[:name]}"
    end
    
    if passed == total
      puts "\n🎉 ALL TESTS PASSED! Refactoring is successful."
    else
      puts "\n💥 SOME TESTS FAILED! Please review the refactoring changes."
    end
  end
end

# Main execution
if __FILE__ == $0
  begin
    baseline_dir = ARGV[0]  # Optional baseline directory argument
    tester = FullTester.new(baseline_dir)
    success = tester.run_full_test
    
    exit success ? 0 : 1
    
  rescue Interrupt
    puts "\n❌ Full test cancelled by user"
    exit 1
  rescue => e
    puts "\n❌ Error running full test: #{e.message}"
    puts "🐛 #{e.backtrace.join("\n   ")}" if ENV['DEBUG']
    exit 1
  end
end