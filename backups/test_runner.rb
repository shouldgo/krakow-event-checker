#!/usr/bin/env ruby

# test_runner.rb - Master test orchestrator for refactoring validation
#
# This script provides a unified interface for running all types of tests
# during the refactoring process.
#
# Usage: 
#   ruby test_runner.rb baseline    # Create baseline tests
#   ruby test_runner.rb quick       # Run quick validation
#   ruby test_runner.rb full        # Run comprehensive test
#   ruby test_runner.rb all         # Run everything

class TestRunner
  def initialize
    @scripts_dir = Dir.pwd
    puts "🧪 Event Checker Test Runner"
    puts "=" * 40
  end
  
  def run(command)
    case command&.downcase
    when 'baseline', 'create'
      create_baseline
    when 'quick', 'fast'
      run_quick_test
    when 'full', 'comprehensive'
      run_full_test
    when 'all', 'complete'
      run_all_tests
    else
      show_usage
    end
  end
  
  private
  
  def create_baseline
    puts "📋 Creating baseline test data..."
    puts "This will run the current version to establish comparison benchmarks."
    puts
    
    unless File.exist?('create_baseline.rb')
      puts "❌ create_baseline.rb not found!"
      exit 1
    end
    
    success = system('ruby create_baseline.rb')
    
    if success
      puts "\n✅ Baseline creation completed!"
    else
      puts "\n❌ Baseline creation failed!"
      exit 1
    end
  end
  
  def run_quick_test
    puts "⚡ Running quick validation test..."
    puts "This performs a fast check that basic functionality works."
    puts
    
    unless File.exist?('quick_test.rb')
      puts "❌ quick_test.rb not found!"
      exit 1
    end
    
    success = system('ruby quick_test.rb')
    
    if success
      puts "\n✅ Quick test passed!"
    else
      puts "\n❌ Quick test failed!"
      exit 1
    end
  end
  
  def run_full_test
    puts "🧪 Running comprehensive validation test..."
    puts "This compares current version against established baselines."
    puts
    
    unless File.exist?('full_test.rb')
      puts "❌ full_test.rb not found!"
      exit 1
    end
    
    # Check if baselines exist
    baseline_dirs = Dir.glob('test_baselines/*').select { |d| Dir.exist?(d) }
    if baseline_dirs.empty?
      puts "⚠️  No baselines found! Creating them first..."
      create_baseline
      puts
    end
    
    success = system('ruby full_test.rb')
    
    if success
      puts "\n✅ Full test passed!"
    else
      puts "\n❌ Full test failed!"
      exit 1
    end
  end
  
  def run_all_tests
    puts "🎯 Running complete test suite..."
    puts "This will create baselines (if needed) and run all validations."
    puts
    
    # Check if baselines exist, create if needed
    baseline_dirs = Dir.glob('test_baselines/*').select { |d| Dir.exist?(d) }
    if baseline_dirs.empty?
      puts "📋 Step 1: Creating baselines..."
      create_baseline
      puts
    else
      puts "📋 Step 1: Baselines already exist, skipping creation..."
      puts
    end
    
    # Run quick test
    puts "⚡ Step 2: Running quick test..."
    unless system('ruby quick_test.rb')
      puts "❌ Quick test failed! Aborting full test suite."
      exit 1
    end
    puts
    
    # Run full test
    puts "🧪 Step 3: Running comprehensive test..."
    unless system('ruby full_test.rb')
      puts "❌ Full test failed!"
      exit 1
    end
    
    puts "\n🎉 ALL TESTS PASSED! Complete validation successful."
  end
  
  def show_usage
    puts <<~USAGE
      Usage: ruby test_runner.rb <command>
      
      Commands:
        baseline, create     Create baseline test data from current version
        quick, fast         Run quick validation test (2-3 minutes)
        full, comprehensive  Run comprehensive validation against baselines (5-10 minutes)
        all, complete       Run complete test suite (create baselines + all tests)
        
      Examples:
        ruby test_runner.rb baseline     # Before starting refactoring
        ruby test_runner.rb quick        # After each small change
        ruby test_runner.rb full         # After major changes
        ruby test_runner.rb all          # Complete validation
        
      Typical Refactoring Workflow:
        1. ruby test_runner.rb baseline  # Create baseline data
        2. Make refactoring changes
        3. ruby test_runner.rb quick     # Quick validation
        4. Continue refactoring
        5. ruby test_runner.rb full      # Comprehensive validation
        
      The test suite ensures that refactoring preserves all functionality
      by comparing outputs from the original and modified versions.
    USAGE
  end
end

# Main execution
if __FILE__ == $0
  begin
    runner = TestRunner.new
    runner.run(ARGV[0])
    
  rescue Interrupt
    puts "\n❌ Test runner cancelled by user"
    exit 1
  rescue => e
    puts "\n❌ Error in test runner: #{e.message}"
    puts "🐛 #{e.backtrace.join("\n   ")}" if ENV['DEBUG']
    exit 1
  end
end