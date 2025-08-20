# Baseline Test Summary: small_range

**Description**: 2-day range test
**Date Range**: 2025-08-20 to 2025-08-21
**Created**: 2025-08-20 16:03:41
**Ruby Version**: 3.4.1

## Test Scenario
- Start Date: 2025-08-20
- End Date: 2025-08-21
- Duration: 2 days

## Files Generated
- after_ongoing.md
- after_upcoming.md
- before_ongoing.md
- before_upcoming.md
- execution_log.txt
- input.txt

## Usage
This baseline can be used to validate refactoring changes by:
1. Running the same test scenario with refactored code
2. Comparing output files for differences
3. Ensuring functionality is preserved

## Validation Command
```bash
# Run the same test scenario
echo "2025-08-20\n2025-08-21" | ruby event_checker.rb

# Compare outputs
diff after_upcoming.md upcoming.md
diff after_ongoing.md ongoing.md  
diff after_archive.md archive.md
```
