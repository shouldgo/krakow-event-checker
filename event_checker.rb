#!/usr/bin/env ruby

# Kraków Event Checker
# Scrapes events from major cultural websites in Kraków
# and maintains organized markdown files for event planning

require 'net/http'
require 'uri'
require 'date'
require 'json'
require 'digest'
require 'fileutils'
require 'set'
require 'openssl'

# Check if nokogiri is available, install if needed
begin
  require 'nokogiri'
rescue LoadError
  puts "❌ Missing required gem: nokogiri"
  puts "🔧 Installing nokogiri..."
  system("gem install nokogiri")
  require 'nokogiri'
end

class EventChecker
  VERSION = "1.0.0"
  
  # ============================================================================
  # CONFIGURATION SECTION
  # ============================================================================
  
  # File paths
  UPCOMING_FILE = 'upcoming.md'
  ONGOING_FILE = 'ongoing.md'
  ARCHIVE_FILE = 'archive.md'
  THEATER_FILE = 'theater.md'

  # Event type filters
  THEATER_EVENT_TYPE = 'spektakle teatralne'

  # Event categorization thresholds (in days)
  ONGOING_EVENT_THRESHOLD = 30    # Events longer than this go to ongoing.md
  PERMANENT_EVENT_THRESHOLD = 90  # Events longer than this are considered permanent
  TEMPORARY_EXHIBITION_DURATION = 120  # Default duration for temporary exhibitions (4 months)
  PERMANENT_EXHIBITION_DURATION = 3650 # Default duration for permanent exhibitions (10 years)
  
  # Date range defaults
  DEFAULT_DATE_RANGE_DAYS = 7     # Default search range when no end date provided
  MAX_DATE_RANGE_WARNING = 30     # Warn user when range exceeds this many days
  
  # Web scraping configuration
  HTTP_TIMEOUT_SECONDS = 30       # HTTP request timeout
  KARNET_EVENTS_PER_PAGE = 12     # Karnet consistently shows this many events per page
  KARNET_SEARCH_RADIUS = 1000     # Search radius parameter for Karnet
  SLEEP_BETWEEN_REQUESTS = 1      # Seconds to wait between page requests
  
  # Output formatting
  MAX_NEW_EVENTS_DISPLAY = 5      # Maximum new events to show in summary
  MAX_FILTERED_EVENTS_DISPLAY = 10 # Maximum filtered events to show in logs
  MIN_EVENT_TITLE_LENGTH = 3      # Minimum title length for valid events
  MIN_LINK_TEXT_LENGTH = 10       # Minimum link text length for event detection
  
  # User agent string for web requests
  USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
  
  # Website configurations
  WEBSITES = {
    karnet: {
      name: "Karnet Kraków Culture",
      base_url: "https://karnet.krakowculture.pl",
      strategy: :dynamic  # May need special handling for JS-loaded content
    },
    krakow: {
      name: "Official Kraków Calendar", 
      base_url: "https://www.krakow.pl",
      calendar_path: "/kalendarium/1919,shw,{date},1,day.html",
      strategy: :static   # Static HTML with URL-based filtering
    }
  }
  
  # ============================================================================
  # END CONFIGURATION SECTION
  # ============================================================================
  
  # ============================================================================
  # METHOD ORGANIZATION
  # ============================================================================
  # This class is organized into the following sections:
  #
  # 1. INITIALIZATION & MAIN CONTROL FLOW
  #    - initialize, run, debug_log
  #
  # 2. USER INPUT & DATE HANDLING
  #    - get_date_range, parse_date
  #
  # 3. EXISTING DATA LOADING
  #    - load_existing_events, load_events_from_file, parse_ongoing_markdown, 
  #      parse_markdown_event_block
  #
  # 4. WEB SCRAPING - ORCHESTRATION
  #    - scrape_all_websites
  #
  # 5. WEB SCRAPING - KRAKOW.PL
  #    - scrape_krakow_events, get_krakow_total_pages, fetch_krakow_events,
  #      parse_krakow_html_simple, extract_krakow_event_data_simple
  #
  # 6. WEB SCRAPING - KARNET
  #    - scrape_karnet_events, get_karnet_total_events, fetch_karnet_events,
  #      parse_karnet_html, extract_karnet_event_data_simple
  #
  # 7. EVENT PROCESSING & UTILITIES
  #    - detect_exhibition_duration, date_in_range?
  #
  # 8. DATA PROCESSING
  #    - process_events, deduplicate_events, generate_event_signature,
  #      filter_events_by_date, categorize_events
  #
  # 9. FILE OUTPUT & MANAGEMENT
  #    - update_files, detect_new_ongoing_events, move_past_events_to_archive,
  #      generate_ongoing_file, generate_upcoming_file
  #
  # 10. CONTENT GENERATION
  #     - build_ongoing_content, build_upcoming_content
  #
  # 11. EVENT CLASSIFICATION & FORMATTING
  #     - is_permanent_event?, is_multiday_event?, format_event_markdown,
  #       format_multiday_event_markdown, get_preferred_url, format_date_range,
  #       format_date_range_friendly
  # ============================================================================
  
  # ============================================================================
  # 1. INITIALIZATION & MAIN CONTROL FLOW
  # ============================================================================
  
  def initialize
    @events = []
    @debug = ENV['DEBUG'] == '1'
    @existing_upcoming = []
    @existing_archive = []
    
    puts "🎭 Kraków Event Checker v#{VERSION}"
    puts "=" * 40
  end

  def run
    # Load existing events for comparison
    load_existing_events
    
    # Get user input for date range
    date_range = get_date_range
    return false unless date_range
    
    start_date, end_date = date_range
    puts "\n📅 Searching for events from #{start_date} to #{end_date}..."
    
    # Scrape events from both websites
    scrape_all_websites(start_date, end_date)
    
    # Process the collected events
    process_events(start_date, end_date)
    
    # Update files
    update_files
    
    puts "\n✅ Event check completed!"
    puts "📄 Check #{UPCOMING_FILE} for upcoming events"
    puts "🗓️  Check #{ONGOING_FILE} for ongoing events (>#{ONGOING_EVENT_THRESHOLD} days)"
    puts "🎭 Check #{THEATER_FILE} for theater performances"

    # Report new ongoing events
    if @new_ongoing_events && @new_ongoing_events.any?
      puts "🆕 Found #{@new_ongoing_events.length} new ongoing events:"
      @new_ongoing_events.first(MAX_NEW_EVENTS_DISPLAY).each do |event|
        event_type = event[:event_type] ? "#{event[:event_type]}: " : ""
        puts "   • #{event_type}#{event[:title]}"
      end
      if @new_ongoing_events.length > MAX_NEW_EVENTS_DISPLAY
        puts "   ... and #{@new_ongoing_events.length - MAX_NEW_EVENTS_DISPLAY} more"
      end
    else
      puts "📊 No new ongoing events found"
    end

    # Report theater events count
    if @theater_events && @theater_events.any?
      puts "🎭 Found #{@theater_events.length} theater performances"
    end

    puts "📚 Past events moved to #{ARCHIVE_FILE}" if File.exist?(ARCHIVE_FILE)
    
    true
  end

  private

  def debug_log(message)
    puts "🐛 #{message}" if @debug
  end

  # ============================================================================
  # 2. USER INPUT & DATE HANDLING
  # ============================================================================

  def get_date_range
    puts "\nEnter your search criteria:"
    
    # Get start date
    print "Start date (YYYY-MM-DD) or press Enter for today: "
    start_input = gets.chomp.strip
    
    if start_input.empty?
      start_date = Date.today
    else
      start_date = parse_date(start_input)
      return nil unless start_date
    end
    
    # Get end date
    print "End date (YYYY-MM-DD) or press Enter for #{DEFAULT_DATE_RANGE_DAYS} days from start: "
    end_input = gets.chomp.strip
    
    if end_input.empty?
      end_date = start_date + DEFAULT_DATE_RANGE_DAYS
    else
      end_date = parse_date(end_input)
      return nil unless end_date
    end
    
    # Validate range
    if end_date < start_date
      puts "❌ End date must be after start date!"
      return nil
    end
    
    if (end_date - start_date).to_i > MAX_DATE_RANGE_WARNING
      puts "⚠️  Large date range (#{(end_date - start_date).to_i} days). This might take a while."
      print "Continue? (y/N): "
      return nil unless gets.chomp.downcase.start_with?('y')
    end
    
    [start_date, end_date]
  end

  def parse_date(date_string)
    Date.parse(date_string)
  rescue ArgumentError
    puts "❌ Invalid date format: #{date_string}"
    puts "   Please use YYYY-MM-DD format (e.g., 2025-08-20)"
    nil
  end

  # ============================================================================
  # 3. EXISTING DATA LOADING
  # ============================================================================

  def load_existing_events
    debug_log("Loading existing events...")
    @existing_upcoming = load_events_from_file(UPCOMING_FILE)
    @existing_ongoing = load_events_from_file(ONGOING_FILE)
    @existing_archive = load_events_from_file(ARCHIVE_FILE)
  end

  def load_events_from_file(filename)
    return [] unless File.exist?(filename)
    
    events = []
    
    begin
      content = File.read(filename)
      
      if filename == ONGOING_FILE
        # Parse ongoing.md with its specific format (markdown list)
        events = parse_ongoing_markdown(content)
      else
        # Parse other files with event separator format
        event_blocks = content.split(/^---\s*$/m)
        
        event_blocks.each do |block|
          event = parse_markdown_event_block(block.strip)
          events << event if event
        end
      end
      
    rescue => e
      debug_log("Error loading events from #{filename}: #{e.message}")
    end
    
    debug_log("Loaded #{events.length} existing events from #{filename}")
    events
  end

  def parse_ongoing_markdown(content)
    events = []
    
    # Match event lines like: - [Event type: Event name](URL) | Date - Date  
    content.scan(/^- \[([^\]]+)\]\(([^)]+)\)(?:[^|]*)(?:\| (.+))?$/) do |title_with_type, url, date_info|
      # Extract event type and title
      if title_with_type.include?(': ')
        event_type, title = title_with_type.split(': ', 2)
      else
        event_type = nil
        title = title_with_type
      end
      
      # Simple data for signature generation
      event = {
        title: title,
        event_type: event_type,
        url: url,
        urls: [url]
      }
      
      events << event
    end
    
    debug_log("Parsed #{events.length} events from ongoing markdown")
    events
  end

  def parse_markdown_event_block(block)
    return nil if block.empty?
    
    lines = block.split("\n").map(&:strip).reject(&:empty?)
    return nil if lines.empty?
    
    # Find title (starts with ###)
    title_line = lines.find { |line| line.start_with?('###') }
    return nil unless title_line
    
    # Extract title
    title = title_line.gsub(/^###\s*/, '').strip
    clean_title = title.strip
    
    # Extract other fields
    description = nil
    location = nil
    time = nil
    date_start = Date.today
    date_end = Date.today
    urls = []
    
    lines.each do |line|
      case line
      when /^\*\*Date:\*\*\s*(.+)$/
        date_text = $1.strip
        if date_text =~ /(\d{4}-\d{2}-\d{2})\s*-\s*(\d{4}-\d{2}-\d{2})/
          date_start = Date.parse($1) rescue date_start
          date_end = Date.parse($2) rescue date_end
        elsif date_text =~ /(\d{4}-\d{2}-\d{2})/
          date_start = Date.parse($1) rescue date_start
          date_end = date_start
        end
      when /^\*\*Time:\*\*\s*(.+)$/
        time = $1.strip
      when /^\*\*Location:\*\*\s*(.+)$/
        location = $1.strip
      when /^\*\*Description:\*\*\s*(.+)$/
        description = $1.strip
      when /^-\s*\[.+\]\((.+)\)$/
        urls << $1.strip
      end
    end
    
    {
      title: clean_title,
      description: description,
      location: location,
      time: time,
      date_start: date_start,
      date_end: date_end,
      urls: urls
    }
    
  rescue => e
    debug_log("Error parsing event block: #{e.message}")
    nil
  end

  # ============================================================================
  # 4. WEB SCRAPING - ORCHESTRATION
  # ============================================================================

  def scrape_all_websites(start_date, end_date)
    puts "\n🌐 Fetching events from websites..."
    
    # Scrape Karnet first (primary data source with complete coverage)
    scrape_karnet_events(start_date, end_date)
    
    # Scrape Krakow.pl second (secondary source for cross-reference)
    scrape_krakow_events(start_date, end_date)
    
    puts "📊 Total events collected: #{@events.length}"
  end

  # ============================================================================
  # 5. WEB SCRAPING - KRAKOW.PL
  # ============================================================================

  def scrape_krakow_events(start_date, end_date)
    puts "   → krakow.pl calendar..."
    
    begin
      events_found = 0
      all_events = []
      
      # Build filtered URL for date range
      search_url = "#{WEBSITES[:krakow][:base_url]}/kalendarium/1919,findk,0,#{start_date.strftime('%Y-%m-%d')},#{end_date.strftime('%Y-%m-%d')},search,,,,res.html"
      debug_log("Fetching first krakow.pl page to determine total pages: #{search_url}")
      
      # Get total page count from first page
      total_pages = get_krakow_total_pages(search_url)
      
      if total_pages > 0
        debug_log("Found #{total_pages} total pages to scrape")
        puts "     📊 Krakow.pl shows #{total_pages} pages, scraping all..."
      else
        total_pages = 1  # Fallback
        debug_log("Could not determine total pages, defaulting to 1 page")
      end
      
      # Now scrape all pages (0-indexed)
      (0...total_pages).each do |page|
        url = "#{WEBSITES[:krakow][:base_url]}/kalendarium/1919,findk,#{page},#{start_date.strftime('%Y-%m-%d')},#{end_date.strftime('%Y-%m-%d')},search,,,,res.html"
        debug_log("Fetching krakow.pl page #{page + 1}/#{total_pages}")
        
        page_events = fetch_krakow_events(url, start_date, end_date)
        
        if page_events.any?
          all_events.concat(page_events)
          events_found += page_events.length
        else
          debug_log("No events found on page #{page + 1}")
        end
        
        # Be polite to the server
        sleep(SLEEP_BETWEEN_REQUESTS) if page > 0
      end
      
      @events.concat(all_events)
      puts "     ✅ Found #{events_found} events from krakow.pl (#{all_events.length} unique)"
      
    rescue => e
      puts "     ❌ Error scraping krakow.pl: #{e.message}"
      debug_log(e.backtrace.first) if @debug
    end
  end

  def get_krakow_total_pages(url)
    begin
      uri = URI(url)
      http, request = create_http_client(uri)
      
      response = http.request(request)
      
      if response.code == '200'
        doc = Nokogiri::HTML(response.body)
        
        # Find pagination list and count pages
        pagination = doc.css('.pagination__list').first
        if pagination
          # Count pagination links (excluding previous/next)
          page_links = pagination.css('a').select { |link| link.text.strip.match?(/^\d+$/) }
          total_pages = page_links.map { |link| link.text.strip.to_i }.max || 1
          debug_log("Parsed total pages: #{total_pages}")
          return total_pages
        else
          debug_log("Could not find .pagination__list element")
          return 1
        end
      else
        debug_log("HTTP #{response.code} for #{url}")
        return 1
      end
      
    rescue => e
      debug_log("Error getting total pages: #{e.message}")
      return 1
    end
  end

  def fetch_krakow_events(url, start_date, end_date)
    events = []
    
    begin
      uri = URI(url)
      http, request = create_http_client(uri)
      
      response = http.request(request)
      
      if response.code == '200'
        events = parse_krakow_html_simple(response.body, start_date, end_date)
      else
        debug_log("HTTP #{response.code} for #{url}")
      end
      
    rescue => e
      debug_log("Error fetching #{url}: #{e.message}")
    end
    
    events
  end

  def parse_krakow_html_simple(html, start_date, end_date)
    events = []
    
    begin
      doc = Nokogiri::HTML(html)
      
      # Try much broader container selection - any div with a link that could be an event
      event_containers = doc.css('div').select do |container|
        # Must have some substantial content and a link
        container.text.length > 20 &&
        container.css('a').any? &&
        (container.css('h3').any? || 
         container.text.match?(/\d{4}-\d{2}-\d{2}/) ||
         container['class']&.include?('event'))
      end
      
      debug_log("Found #{event_containers.length} event containers in krakow.pl")
      
      seen_urls = Set.new
      extraction_count = 0
      
      event_containers.each_with_index do |container, index|
        debug_log("Processing container #{index + 1}/#{event_containers.length}")
        event = extract_krakow_event_data_simple(container, start_date, end_date)
        if event && !seen_urls.include?(event[:url])
          events << event
          seen_urls << event[:url]
          extraction_count += 1
          debug_log("✅ Extracted #{extraction_count}: #{event[:title]} (#{event[:date_start]})")
        elsif event && seen_urls.include?(event[:url])
          debug_log("❌ Duplicate URL: #{event[:title]}")
        else
          debug_log("❌ Failed extraction for container #{index + 1}")
        end
      end
      
      debug_log("Successfully extracted #{events.length} unique events from krakow.pl")
      
    rescue => e
      debug_log("Error parsing krakow.pl HTML: #{e.message}")
    end
    
    events
  end

  def extract_krakow_event_data_simple(container, start_date, end_date)
    begin
      # Extract title from any heading or strong text
      title_element = container.css('h3.text__title, h3, h2, h4, strong').first
      if !title_element
        # Try link text as title
        title_element = container.css('a').first
      end
      if !title_element
        debug_log("No title element found in container")
        return nil
      end
      title = title_element.text.strip
      if title.empty? || title.length < MIN_EVENT_TITLE_LENGTH
        debug_log("Title too short or empty: '#{title}'")
        return nil
      end
      
      # Extract date from anywhere in the container
      date_text = nil
      date_match = container.text.match(/(\d{4}-\d{2}-\d{2})/)
      if date_match
        date_text = date_match[1]
      else
        debug_log("No date pattern found for event: '#{title}'")
        return nil
      end
      
      event_date = Date.parse(date_text) rescue nil
      if !event_date
        debug_log("Could not parse date '#{date_text}' for event: '#{title}'")
        return nil
      end
      
      # Handle permanent exhibitions - detect by old dates, keywords, or container text
      container_text = container.text.downcase
      is_permanent = event_date < Date.new(2025, 1, 1) ||  # Events from 2024 and earlier
                    title.match?(/wystawa stała|muzeum.*stała|galeria.*stała|ekspozycja stała|stała wystawa/i) ||
                    title.match?(/gabinet|izba|sala|trasa|skarby|ogrody|smocza jama|wawel|klasztorek/i) ||
                    title.match?(/broń i barwa|historia a oskar|lapidarium|fonografii|ślusarstwa|solniczki/i) ||
                    title.match?(/galeria autorska|technoczułość|muzeum książąt|niepołomice.*miasto/i) ||
                    container_text.include?('wydarzenie stałe') ||
                    container_text.include?('wystawa stała') ||
                    container_text.include?('wystawy stałe')
      
      if is_permanent
        # Permanent exhibition - use search date for categorization
        event_start_date = start_date
        event_end_date = start_date + PERMANENT_EXHIBITION_DURATION  # Long duration for categorization
        debug_log("Permanent exhibition detected: '#{title}'")
      else
        # Regular event - use actual dates
        event_start_date = event_date  
        event_end_date = event_date
        debug_log("Regular event: '#{title}' (#{event_date})")
      end
      
      # Extract URL from any link in the container
      url_element = container.css('a').first
      return nil unless url_element && url_element['href']
      
      href = url_element['href']
      url = href.start_with?('http') ? href : WEBSITES[:krakow][:base_url] + href
      
      # Extract time if present in the container text
      time_match = container.text.match(/\b(\d{1,2}:\d{2})\b/)
      time = time_match ? time_match[1] : nil
      
      {
        title: title,
        time: time,
        date_start: event_start_date,
        date_end: event_end_date,
        url: url,
        urls: [url],
        source: 'krakow.pl'
      }
      
    rescue => e
      debug_log("Error extracting simple krakow.pl event: #{e.message}")
      nil
    end
  end

  # ============================================================================
  # 6. WEB SCRAPING - KARNET
  # ============================================================================

  def scrape_karnet_events(start_date, end_date)
    puts "   → karnet.krakowculture.pl..."
    
    begin
      events_found = 0
      all_events = []
      
      # First, get the first page to determine total event count
      first_url = build_karnet_url(start_date, end_date, 1)
      debug_log("Fetching first Karnet page to determine total events: #{first_url}")
      
      # Get total event count from first page
      total_events, events_per_page = get_karnet_total_events(first_url)
      
      if total_events > 0
        total_pages = (total_events.to_f / events_per_page).ceil
        debug_log("Found #{total_events} total events, #{events_per_page} per page = #{total_pages} pages to scrape")
        puts "     📊 Karnet shows #{total_events} events, scraping #{total_pages} pages..."
      else
        total_pages = 1  # Fallback
        debug_log("Could not determine total events, defaulting to 1 page")
      end
      
      # Now scrape all pages
      (1..total_pages).each do |page|
        url = build_karnet_url(start_date, end_date, page)
        debug_log("Fetching Karnet page #{page}/#{total_pages}")
        
        page_events = fetch_karnet_events(url, start_date, end_date)
        
        if page_events.any?
          all_events.concat(page_events)
          events_found += page_events.length
        else
          debug_log("No events found on page #{page}")
        end
        
        # Be polite to the server
        sleep(SLEEP_BETWEEN_REQUESTS) if page > 1
      end
      
      @events.concat(all_events)
      puts "     ✅ Found #{events_found} events from karnet.krakowculture.pl (#{all_events.length} unique)"
      
      # Show comparison with expected count
      if total_events > 0 && events_found != total_events
        puts "     ℹ️  Expected #{total_events} events, got #{events_found} (difference: #{total_events - events_found})"
      end
      
    rescue => e
      puts "     ❌ Error scraping karnet.krakowculture.pl: #{e.message}"
      debug_log(e.backtrace.first) if @debug
    end
  end

  def get_karnet_total_events(url)
    begin
      uri = URI(url)
      http, request = create_http_client(uri)
      
      response = http.request(request)
      
      if response.code == '200'
        doc = Nokogiri::HTML(response.body)
        
        # Parse total events from <span id="totalEvents">(183)</span>
        total_element = doc.css('#totalEvents').first
        if total_element
          total_text = total_element.text.strip
          total_events = total_text.scan(/\d+/).first.to_i
          debug_log("Parsed total events: #{total_events}")
        else
          debug_log("Could not find #totalEvents element")
          total_events = 0
        end
        
        # Count events on first page to estimate events per page
        event_links = doc.css('a[href*="/"][href*="-krakow-"]').select do |link|
          href = link['href']
          text = link.text.strip
          href.match?(/\/\d+-krakow-/) && text.length > MIN_LINK_TEXT_LENGTH &&
          !href.include?('wydarzenia/') && !text.include?('Zobacz wszystkie') &&
          !text.include?('Moje wydarzenia') && !text.include?('Szukaj')
        end.length
        
        events_per_page = KARNET_EVENTS_PER_PAGE  # Karnet consistently shows this many unique events per page
        debug_log("Events per page: #{events_per_page}")
        
        return [total_events, events_per_page]
      else
        debug_log("HTTP #{response.code} for #{url}")
        return [0, KARNET_EVENTS_PER_PAGE]  # Fallback
      end
      
    rescue => e
      debug_log("Error getting total events: #{e.message}")
      return [0, 12]  # Fallback
    end
  end

  def fetch_karnet_events(url, start_date, end_date)
    events = []
    
    begin
      uri = URI(url)
      http, request = create_http_client(uri)
      
      response = http.request(request)
      
      if response.code == '200'
        events = parse_karnet_html(response.body, start_date, end_date)
      else
        debug_log("HTTP #{response.code} for #{url}")
      end
      
    rescue => e
      debug_log("Error fetching #{url}: #{e.message}")
    end
    
    events
  end

  def parse_karnet_html(html, start_date, end_date)
    events = []
    
    begin
      doc = Nokogiri::HTML(html)
      
      # Find all event containers - look for elements that contain both title and date
      event_containers = doc.css('.event-item, .card, .list-item').select do |container|
        container.css('h3.event-title').any? && container.css('.event-date').any?
      end
      
      # Fallback: find any containers with event URLs
      if event_containers.empty?
        event_containers = doc.css('a[href*="krakow-"]').map(&:parent).uniq.select do |container|
          container.css('h3').any? || container.text.include?('.2025')
        end
      end
      
      debug_log("Found #{event_containers.length} event containers in Karnet")
      
      seen_urls = Set.new
      
      event_containers.each do |container|
        event = extract_karnet_event_data_simple(container, start_date, end_date)
        if event && !seen_urls.include?(event[:url])
          events << event
          seen_urls << event[:url]
          debug_log("Extracted: #{event[:title]} (#{event[:date_start]} - #{event[:date_end]})")
        end
      end
      
      debug_log("Successfully extracted #{events.length} unique events from Karnet")
      
    rescue => e
      debug_log("Error parsing Karnet HTML: #{e.message}")
    end
    
    events
  end

  def extract_karnet_event_data_simple(container, start_date, end_date)
    begin
      # Extract title from h3.event-title or h3
      title_element = container.css('h3.event-title').first || container.css('h3').first
      return nil unless title_element
      title = title_element.text.strip
      return nil if title.empty? || title.length < MIN_EVENT_TITLE_LENGTH
      
      # Extract date from .event-date span or similar
      date_element = container.css('.event-date span').first || 
                    container.css('.event-date').first ||
                    container.css('a[class*="date"]').first
      
      # Extract URL from container or its children
      url_element = container.css('a[href*="krakow-"]').first || container
      return nil unless url_element && url_element['href']
      
      href = url_element['href']
      url = href.start_with?('http') ? href : WEBSITES[:karnet][:base_url] + href
      
      # Parse dates from date element if available
      if date_element
        date_text = date_element.text.strip
        date_matches = date_text.scan(/(\d{2})\.(\d{2})\.(\d{4})/)
        dates = date_matches.map do |day, month, year|
          Date.new(year.to_i, month.to_i, day.to_i) rescue nil
        end.compact
        
        if dates.any?
          event_start = dates.min
          event_end = dates.max
        else
          # Fallback for exhibitions without explicit dates
          event_start = start_date
          event_end = detect_exhibition_duration(title, container, start_date)
        end
      else
        # Fallback for exhibitions without date elements
        event_start = start_date  
        event_end = detect_exhibition_duration(title, container, start_date)
      end
      
      # Extract time if present
      time_text = container.text
      time_match = time_text.match(/\b(\d{1,2}:\d{2})\b/)
      time = time_match ? time_match[1] : nil
      
      # Extract event type from span.event-type
      event_type_element = container.css('span.event-type').first
      event_type = event_type_element ? event_type_element.text.strip : nil
      
      # Only include events in our date range
      return nil unless date_in_range?(event_start, event_end, start_date, end_date)
      
      {
        title: title,
        event_type: event_type,
        time: time,
        date_start: event_start,
        date_end: event_end,
        url: url,
        urls: [url]
      }
      
    rescue => e
      debug_log("Error extracting simple Karnet event: #{e.message}")
      nil
    end
  end

  # ============================================================================
  # 7. EVENT PROCESSING & UTILITIES
  # ============================================================================

  def detect_exhibition_duration(title, container, start_date)
    # Check if it's a permanent exhibition
    container_text = container.text.downcase
    if container_text.include?('wystawa stała') || 
       container_text.include?('wystawy stałe') ||
       container_text.include?('wydarzenie stałe')
      return start_date + PERMANENT_EXHIBITION_DURATION  # 10 years for permanent
    elsif title.match?(/\b(wystawa|ekspozycja|exhibition)\b/i) || container_text.include?('wystawy czasowe')
      return start_date + TEMPORARY_EXHIBITION_DURATION   # 4 months for temporary exhibitions  
    else
      return start_date         # Single day event
    end
  end


  def date_in_range?(event_start, event_end, range_start, range_end)
    # Event overlaps with our search range
    event_start <= range_end && event_end >= range_start
  end

  # Helper method to create HTTP client with standard configuration
  def create_http_client(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = HTTP_TIMEOUT_SECONDS
    
    # Configure SSL to handle certificate issues
    if http.use_ssl?
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      http.ssl_version = :TLSv1_2
    end
    
    request = Net::HTTP::Get.new(uri)
    request['User-Agent'] = USER_AGENT
    
    [http, request]
  end

  # Helper method to build Karnet search URL
  def build_karnet_url(start_date, end_date, page = 1)
    "#{WEBSITES[:karnet][:base_url]}/wydarzenia?query=&date_start=#{start_date.strftime('%Y-%m-%d')}&date_end=#{end_date.strftime('%Y-%m-%d')}&choosenArea=&radius=#{KARNET_SEARCH_RADIUS}&category_id=&Item_page=#{page}"
  end

  # ============================================================================
  # 8. DATA PROCESSING
  # ============================================================================

  def process_events(start_date, end_date)
    puts "\n🔄 Processing events..."
    
    # Remove duplicates
    deduplicate_events
    
    # Skip date filtering - trust website filtering since both sites already filter by date range
    
    # Categorize events
    categorize_events(start_date, end_date)
  end

  def deduplicate_events
    debug_log("Removing duplicate events...")
    
    unique_events = []
    seen_signatures = Set.new
    
    @events.each do |event|
      signature = generate_event_signature(event)
      
      if seen_signatures.include?(signature)
        # Find existing event and merge information
        existing = unique_events.find { |e| generate_event_signature(e) == signature }
        if existing
          # Merge URLs
          event_url = event[:url] 
          existing[:urls] ||= existing[:url] ? [existing[:url]] : []
          existing.delete(:url) if existing[:url]
          
          if event_url && !existing[:urls].include?(event_url)
            existing[:urls] << event_url
          end
          
          # Prefer Karnet data when available (better source)
          if event[:source] == 'karnet' && existing[:source] != 'karnet'
            # Use Karnet's date, location, time data
            existing[:date_start] = event[:date_start] if event[:date_start]
            existing[:date_end] = event[:date_end] if event[:date_end]
            existing[:location] = event[:location] if event[:location] && !event[:location].empty?
            existing[:time] = event[:time] if event[:time] && !event[:time].empty?
            existing[:source] = event[:source]
          end
          
          debug_log("Merged duplicate: #{event[:title]} (#{event[:source]} -> #{existing[:source]})")
        end
      else
        # Convert single URL to array for consistency
        event[:urls] = event[:url] ? [event[:url]] : []
        event.delete(:url)
        
        unique_events << event
        seen_signatures << signature
      end
    end
    
    duplicates_removed = @events.length - unique_events.length
    @events = unique_events
    
    puts "   ✅ Removed #{duplicates_removed} duplicates (#{@events.length} unique events)"
  end

  def generate_event_signature(event)
    # Create signature based on normalized title only for better cross-site matching
    # Don't include date/location as they often differ between sites for the same event
    title = event[:title]&.downcase&.strip&.gsub(/[^\w\s]/, '') || ''
    
    # Remove common time patterns from title to improve matching
    title = title.gsub(/\b\d{1,2}:\d{2}\b/, '').strip
    title = title.gsub(/\s+/, ' ')  # Normalize whitespace
    
    Digest::MD5.hexdigest(title)
  end

  def filter_events_by_date(start_date, end_date)
    debug_log("Filtering events by date range...")
    
    before_count = @events.length
    filtered_out = []
    
    @events.select! do |event|
      event_start = event[:date_start]
      event_end = event[:date_end] || event_start
      
      # Keep events that overlap with our date range
      keep = event_start <= end_date && event_end >= start_date
      
      if !keep
        filtered_out << "#{event[:title]} (#{event_start} - #{event_end}) from #{event[:source]}"
      end
      
      keep
    end
    
    puts "   ✅ #{@events.length} events in date range"
    
    # Always show filtered events if any were removed, regardless of debug mode
    if filtered_out.any?
      puts "📋 Filtered out #{filtered_out.length} events outside range #{start_date} - #{end_date}:"
      filtered_out.first(MAX_FILTERED_EVENTS_DISPLAY).each { |event| puts "   - #{event}" }
      puts "   ... and #{filtered_out.length - MAX_FILTERED_EVENTS_DISPLAY} more" if filtered_out.length > MAX_FILTERED_EVENTS_DISPLAY
    end
  end

  def categorize_events(start_date, end_date)
    debug_log("Categorizing events...")

    @theater_events = []      # Theater performances (go to theater.md)
    @ongoing_events = []      # Events longer than #{ONGOING_EVENT_THRESHOLD} days (go to ongoing.md)
    @multiday_events = []     # Events 1-#{ONGOING_EVENT_THRESHOLD} days (go to upcoming.md)
    @daily_events = {}        # Single day events (go to upcoming.md)

    @events.each do |event|
      event_start = event[:date_start]
      event_end = event[:date_end] || event_start

      duration_days = get_event_duration(event)

      # Separate theater events into dedicated file
      if event[:event_type]&.downcase == THEATER_EVENT_TYPE.downcase
        @theater_events << event
      elsif duration_days > ONGOING_EVENT_THRESHOLD
        @ongoing_events << event
      elsif duration_days > 0
        @multiday_events << event
      else
        # Single day event
        @daily_events[event_start] ||= []
        @daily_events[event_start] << event
      end
    end

    puts "   📊 Theater: #{@theater_events.length}, Ongoing: #{@ongoing_events.length}, Multi-day: #{@multiday_events.length}, Daily: #{@daily_events.values.flatten.length}"
  end

  # ============================================================================
  # 9. FILE OUTPUT & MANAGEMENT
  # ============================================================================

  def update_files
    puts "\n📝 Updating files..."

    # Move past events to archive
    move_past_events_to_archive

    # Detect new ongoing events before generating files
    @new_ongoing_events = detect_new_ongoing_events

    # Generate theater events file
    generate_theater_file

    # Generate ongoing events file
    generate_ongoing_file

    # Generate upcoming events file
    generate_upcoming_file
  end

  def detect_new_ongoing_events
    # If there are no ongoing events in this run, nothing is new
    return [] if @ongoing_events.empty?
    
    # If no existing ongoing file, all current events are new
    return @ongoing_events if @existing_ongoing.empty?
    
    # Create signatures for existing ongoing events
    existing_signatures = Set.new
    @existing_ongoing.each do |event|
      signature = generate_event_signature(event)
      existing_signatures << signature
    end
    
    # Find new ongoing events by comparing signatures
    new_events = []
    @ongoing_events.each do |event|
      signature = generate_event_signature(event)
      unless existing_signatures.include?(signature)
        new_events << event
        debug_log("New ongoing event detected: #{event[:title]}")
      end
    end
    
    debug_log("Found #{new_events.length} new ongoing events")
    new_events
  end

  def move_past_events_to_archive
    return if @existing_upcoming.empty?
    
    today = Date.today
    past_events = []
    current_events = []
    
    @existing_upcoming.each do |event|
      if event[:date_end] < today
        past_events << event
        debug_log("Moving to archive: #{event[:title]}")
      else
        current_events << event
      end
    end
    
    if past_events.any?
      # Append past events to archive file
      archive_content = ""
      
      # Add existing archive content if file exists
      if File.exist?(ARCHIVE_FILE)
        existing_archive = File.read(ARCHIVE_FILE)
        archive_content = existing_archive unless existing_archive.strip.empty?
      end
      
      # Add header if this is a new archive file
      if archive_content.empty?
        archive_content = "# Archived Cultural Events in Kraków\n\n"
        archive_content += "_Events that have passed_\n\n"
      end
      
      # Add past events to archive
      past_events.each do |event|
        archive_content += format_event_markdown(event)
      end
      
      # Write updated archive
      File.write(ARCHIVE_FILE, archive_content)
      
      # Update the in-memory existing events
      @existing_upcoming = current_events
      
      puts "   📚 Moved #{past_events.length} past events to archive"
    else
      debug_log("No past events to archive")
    end
  end

  def generate_ongoing_file
    puts "   → Generating #{ONGOING_FILE}..."
    
    content = build_ongoing_content
    
    File.write(ONGOING_FILE, content)
    puts "     ✅ Updated #{ONGOING_FILE}"
  end

  def generate_upcoming_file
    puts "   → Generating #{UPCOMING_FILE}..."

    content = build_upcoming_content

    File.write(UPCOMING_FILE, content)
    puts "     ✅ Updated #{UPCOMING_FILE}"
  end

  def generate_theater_file
    puts "   → Generating #{THEATER_FILE}..."

    content = build_theater_content

    File.write(THEATER_FILE, content)
    puts "     ✅ Updated #{THEATER_FILE}"
  end

  # ============================================================================
  # 10. CONTENT GENERATION
  # ============================================================================

  def build_ongoing_content
    content = "# Ongoing Cultural Events in Kraków\n\n"
    content += "_Last updated: #{Time.now.strftime('%Y-%m-%d %H:%M')}_\n\n"
    content += "_Generated by Kraków Event Checker v#{VERSION}_\n\n"
    content += "_Events lasting longer than #{ONGOING_EVENT_THRESHOLD} days, organized by type_\n\n"

    if @ongoing_events.empty?
      content += "No ongoing events found.\n"
      return content
    end

    # Add "New Events" section at the top if there are new events
    if @new_ongoing_events && @new_ongoing_events.any?
      content += "## New Events\n\n"
      @new_ongoing_events.sort_by { |event| event[:title] }.each do |event|
        content += format_multiday_event_markdown(event)
      end
      content += "\n"
    end

    # Group ongoing events by event type
    events_by_type = {}
    @ongoing_events.each do |event|
      event_type = event[:event_type] || "Inne" # "Other" in Polish
      events_by_type[event_type] ||= []
      events_by_type[event_type] << event
    end
    
    # Sort event types alphabetically
    events_by_type.keys.sort.each do |event_type|
      content += "## #{event_type}\n\n"
      events_by_type[event_type].sort_by { |event| event[:title] }.each do |event|
        content += format_multiday_event_markdown(event)
      end
      content += "\n"
    end
    
    content
  end

  def build_upcoming_content
    content = "# Upcoming Cultural Events in Kraków\n\n"
    content += "_Last updated: #{Time.now.strftime('%Y-%m-%d %H:%M')}_\n\n"
    content += "_Generated by Kraków Event Checker v#{VERSION}_\n\n"

    if @events.empty?
      content += "No events found for the specified date range.\n"
      return content
    end

    # Note: Ongoing events (>#{ONGOING_EVENT_THRESHOLD} days) are now in ongoing.md

    # Add multi-day events under single section
    if @multiday_events.any?
      content += "## Multi-day events\n\n"
      @multiday_events.sort_by { |event| event[:date_start] }.each do |event|
        content += format_multiday_event_markdown(event)
      end
      content += "\n"
    end

    # Add daily events
    unless @daily_events.empty?
      @daily_events.keys.sort.each do |date|
        content += "## #{date.strftime('%A, %d %b')}\n\n"
        @daily_events[date].each do |event|
          content += format_event_markdown(event)
        end
        content += "\n"
      end
    end

    content
  end

  def build_theater_content
    content = "# Theater Performances in Kraków\n\n"
    content += "_Last updated: #{Time.now.strftime('%Y-%m-%d %H:%M')}_\n\n"
    content += "_Generated by Kraków Event Checker v#{VERSION}_\n\n"
    content += "_Theater performances (spektakle teatralne) organized by date_\n\n"

    if @theater_events.empty?
      content += "No theater performances found.\n"
      return content
    end

    # Group theater events by date
    events_by_date = {}
    @theater_events.each do |event|
      date = event[:date_start]
      events_by_date[date] ||= []
      events_by_date[date] << event
    end

    # Sort by date and output with date headings
    events_by_date.keys.sort.each do |date|
      content += "## #{date.strftime('%A, %d %b')}\n\n"
      events_by_date[date].each do |event|
        content += format_event_markdown(event)
      end
      content += "\n"
    end

    content
  end

  # ============================================================================
  # 11. EVENT CLASSIFICATION & FORMATTING
  # ============================================================================

  def is_permanent_event?(event)
    return false unless has_valid_dates?(event)
    get_event_duration(event) > PERMANENT_EVENT_THRESHOLD
  end

  def is_multiday_event?(event)
    return false unless has_valid_dates?(event)
    duration = get_event_duration(event)
    duration > 0 && duration <= PERMANENT_EVENT_THRESHOLD
  end

  # Helper method to check if event has valid start and end dates
  def has_valid_dates?(event)
    event[:date_start] && event[:date_end]
  end

  # Helper method to calculate event duration in days
  def get_event_duration(event)
    return 0 unless has_valid_dates?(event)
    (event[:date_end] - event[:date_start]).to_i
  end

  def format_event_markdown(event)
    title = event[:title]
    
    # Add event type prefix if available (only for Karnet events)
    if event[:event_type] && !event[:event_type].empty?
      title = "#{event[:event_type]}: #{title}"
    end
    
    # Find the best URL - prioritize Karnet
    url = get_preferred_url(event[:urls])
    
    # Format with time if available
    time_suffix = ""
    if event[:time] && !event[:time].empty? && event[:time].length > 1
      # Clean up time format
      clean_time = event[:time].strip
      time_suffix = " — #{clean_time}"
    end
    
    # Simple format: title as link with optional time
    if url
      "- [#{title}](#{url})#{time_suffix}\n"
    else
      "- #{title}#{time_suffix}\n"
    end
  end
  
  def format_multiday_event_markdown(event)
    title = event[:title]
    
    # Add event type prefix if available (only for Karnet events)
    if event[:event_type] && !event[:event_type].empty?
      title = "#{event[:event_type]}: #{title}"
    end
    
    # Find the best URL - prioritize Karnet
    url = get_preferred_url(event[:urls])
    
    # Format date range in user-friendly format (DD Mon, YY)
    date_range = format_date_range_friendly(event[:date_start], event[:date_end])
    
    # Format with time if available
    time_suffix = ""
    if event[:time] && !event[:time].empty? && event[:time].length > 1
      # Clean up time format
      clean_time = event[:time].strip
      time_suffix = " — #{clean_time}"
    end
    
    # Format: title as link | date range
    if url
      "- [#{title}](#{url})#{time_suffix} | #{date_range}\n"
    else
      "- #{title}#{time_suffix} | #{date_range}\n"
    end
  end

  def get_preferred_url(urls)
    return nil unless urls && urls.any?
    
    # Prioritize Karnet URLs
    karnet_url = urls.find { |url| url.include?('karnet') }
    return karnet_url if karnet_url
    
    # Fallback to first URL
    urls.first
  end

  def format_date_range(start_date, end_date)
    if start_date == end_date
      start_date.strftime('%Y-%m-%d')
    else
      "#{start_date.strftime('%Y-%m-%d')} - #{end_date.strftime('%Y-%m-%d')}"
    end
  end
  
  def format_date_range_friendly(start_date, end_date)
    if start_date == end_date
      start_date.strftime('%d %b, %y')
    else
      "#{start_date.strftime('%d %b, %y')} - #{end_date.strftime('%d %b, %y')}"
    end
  end
end

# Helper method to check Ruby version
def check_ruby_version
  if RUBY_VERSION < '2.0'
    puts "❌ This script requires Ruby 2.0 or higher"
    puts "   Current version: #{RUBY_VERSION}"
    exit 1
  end
end

# Main execution
if __FILE__ == $0
  check_ruby_version
  
  begin
    checker = EventChecker.new
    success = checker.run
    exit success ? 0 : 1
    
  rescue Interrupt
    puts "\n\n❌ Operation cancelled by user"
    exit 1
  rescue => e
    puts "\n❌ An error occurred: #{e.message}"
    puts "   Run with DEBUG=1 for more details" unless ENV['DEBUG']
    puts "🐛 #{e.backtrace.join("\n   ")}" if ENV['DEBUG']
    exit 1
  end
end