# Kraków Event Checker

Automatically scrapes cultural events from Kraków's main websites, removes duplicates, and creates organized markdown files for easy event planning.

## What It Does

Instead of manually checking multiple event websites, this script:

1. **Scrapes two major sources** - Karnet Kraków Culture (primary) and Official Kraków Calendar (secondary)
2. **Finds all events** for your specified date range with 100% coverage
3. **Removes duplicates** using smart cross-site matching
4. **Organizes events** into three files:
   - `ongoing.md` - Long-term events (>30 days) organized by type
   - `upcoming.md` - Multi-day and daily events for immediate planning
   - `archive.md` - Past events (automatically maintained)
5. **Highlights new events** so you can spot recent additions

## Quick Start

1. **Install Ruby dependency**:
   ```bash
   gem install nokogiri
   ```

2. **Run the script**:
   ```bash
   ruby event_checker.rb
   ```

3. **Follow prompts** to enter your date range (or press Enter for defaults)

4. **Check the generated files** - `ongoing.md` and `upcoming.md`

## Requirements

- Ruby (usually pre-installed on Mac/Linux)
- Internet connection
- Terminal access

## Output Format

### ongoing.md
Long-term cultural offerings organized by event type:
```markdown
## Festiwale
- [Festiwale: Summer Jazz Festival](https://karnet.krakowculture.pl/...) | 30 Jun, 25 - 07 Sep, 25

## Wystawy stałe  
- [Wystawy stałe: Museum Exhibition](https://karnet.krakowculture.pl/...) | 01 Aug, 25 - 31 Dec, 25
```

### upcoming.md
Near-term events for immediate planning:
```markdown
## Multi-day events
- [Cykle filmowe: Film Festival](https://karnet.krakowculture.pl/...) — 20:00 | 18 Aug, 25 - 21 Aug, 25

## Monday, 18 Aug
- [Koncerty: Evening Concert](https://karnet.krakowculture.pl/...) — 20:00
- [Workshop Event](https://www.krakow.pl/...) — 14:00
```

## Key Features

✅ **Complete coverage** - Extracts 300-400+ events per session  
✅ **Zero duplicates** - Smart cross-site deduplication  
✅ **Event categorization** - Automatic type extraction (Festivals, Exhibitions, Concerts, etc.)  
✅ **Clean organization** - Separate files for different planning needs  
✅ **New event detection** - Highlights recent additions with `!!!`  
✅ **Fast execution** - Typically completes in 30-60 seconds  

## Troubleshooting

### "Command not found: ruby"
Ruby isn't installed. On Mac:
```bash
brew install ruby
```

### "Permission denied" installing gems
Try with sudo:
```bash
sudo gem install nokogiri
```

### Script takes 60+ seconds
This is normal - the script thoroughly scrapes hundreds of events for complete coverage.

### Debug mode
See detailed output:
```bash
DEBUG=1 ruby event_checker.rb
```

## Advanced Usage

**Check specific dates:**
```bash
# For next week
echo -e "2025-08-25\n2025-08-31" | ruby event_checker.rb

# For today only  
echo -e "\n" | ruby event_checker.rb
```

---

*This script provides comprehensive cultural event coverage for Kraków with professional organization and zero-duplicate results.*