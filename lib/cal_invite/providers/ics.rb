# frozen_string_literal: true

# lib/cal_invite/providers/ics.rb
module CalInvite
  module Providers
    # Generic ICS provider for generating standard iCalendar (.ics) files.
    # This provider generates ICS files that are compatible with most calendar applications.
    # Supports all-day events, regular events, and multi-day sessions with proper timezone handling.
    #
    # This is the single RFC 5545 generator for the gem: {Ical} and {IcsContent}
    # are subclasses kept for their public names and produce identical output.
    #
    # @example Creating a regular event ICS file
    #   event = CalInvite::Event.new(
    #     title: "Team Meeting",
    #     start_time: Time.now,
    #     end_time: Time.now + 3600,
    #     timezone: 'America/New_York'
    #   )
    #   ics = CalInvite::Providers::Ics.new(event)
    #   ics_content = ics.generate
    #
    # @example Creating an all-day event ICS file
    #   event = CalInvite::Event.new(
    #     title: "Company Holiday",
    #     all_day: true,
    #     start_time: Date.today,
    #     end_time: Date.today + 1
    #   )
    #   ics_content = CalInvite::Providers::Ics.new(event).generate
    #
    # @example Creating a multi-day event ICS file
    #   event = CalInvite::Event.new(
    #     title: "Conference",
    #     multi_day_sessions: [
    #       { start_time: Time.parse("2024-04-01 09:00"), end_time: Time.parse("2024-04-01 17:00") },
    #       { start_time: Time.parse("2024-04-02 09:00"), end_time: Time.parse("2024-04-02 17:00") }
    #     ]
    #   )
    #   ics_content = CalInvite::Providers::Ics.new(event).generate
    class Ics < BaseProvider
      # Generates the complete ICS calendar content with proper calendar properties.
      # Handles all event types: all-day, regular, and multi-day sessions.
      #
      # @return [String] The complete ICS calendar content in iCalendar format
      def generate
        calendar_lines = [
          "BEGIN:VCALENDAR",
          "VERSION:2.0",
          "PRODID:-//CalInvite//EN",
          "CALSCALE:GREGORIAN",
          "METHOD:#{method_value}"
        ]

        calendar_lines << "X-WR-CALNAME:#{escape_text(event.calendar_name)}" if event.calendar_name

        unless event.all_day
          calendar_lines.concat(vtimezone_lines || [])
        end

        if event.all_day
          calendar_lines.concat(generate_all_day_event)
        elsif event.multi_day_sessions.any?
          event.multi_day_sessions.each do |session|
            calendar_lines.concat(generate_vevent(session[:start_time], session[:end_time]))
          end
        else
          calendar_lines.concat(generate_vevent(event.start_time, event.end_time))
        end

        calendar_lines << "END:VCALENDAR"
        ensure_single_line_values!(calendar_lines)
        calendar_lines.map { |line| fold_line(line) }.join("\r\n")
      end

      private

      # Maximum content line length in octets, excluding the CRLF (RFC 5545 §3.1).
      MAX_LINE_OCTETS = 75

      # Folds a content line longer than 75 octets into CRLF + single-space
      # continuation lines (RFC 5545 §3.1). Splits only between characters, so a
      # multi-byte UTF-8 character is never cut in half.
      #
      # @param line [String] A single unfolded content line
      # @return [String] The folded line (unchanged if already short enough)
      def fold_line(line)
        return line if line.bytesize <= MAX_LINE_OCTETS

        segments = [+""]
        line.each_char do |char|
          segments << +" " if segments.last.bytesize + char.bytesize > MAX_LINE_OCTETS
          segments.last << char
        end
        segments.join("\r\n")
      end

      # Last line of defense against content-line injection: a CR or LF inside a
      # value would end the line and let the rest of the value be parsed as new
      # properties/components. TEXT values are escaped before reaching here, so
      # this only fires for unescaped values (UID, URL, RRULE, emails, ...).
      #
      # @param lines [Array<String>] The content lines about to be joined
      # @raise [ArgumentError] if any line contains a CR or LF
      # @return [void]
      def ensure_single_line_values!(lines)
        line = lines.find { |l| l.match?(/[\r\n]/) }
        return unless line

        raise ArgumentError, "#{line[/\A[A-Z-]+/]} value must not contain line breaks"
      end

      # Generates an all-day event component (VEVENT) with appropriate formatting.
      # Defaults to today (and a one-day span) when start/end times are omitted.
      #
      # @return [Array<String>] Array of iCalendar format lines for the all-day event
      def generate_all_day_event
        start_date = event.start_time || Time.now
        end_date = event.end_time || (start_date + 86400)
        vevent = [
          "BEGIN:VEVENT",
          "UID:#{event.uid}",
          "DTSTAMP:#{format_timestamp(Time.now.utc)}",
          "DTSTART;VALUE=DATE:#{format_date(start_date)}",
          "DTEND;VALUE=DATE:#{format_date(end_date)}",
          "SUMMARY:#{escape_text(event.title)}"
        ]
        add_optional_fields(vevent)
        vevent << "END:VEVENT"
        vevent
      end

      # Generates a regular or multi-day session event component (VEVENT).
      #
      # @param start_time [Time] The event start time
      # @param end_time [Time] The event end time
      # @return [Array<String>] Array of iCalendar format lines for the event
      def generate_vevent(start_time, end_time)
        vevent = [
          "BEGIN:VEVENT",
          "UID:#{event.uid}",
          "DTSTAMP:#{format_timestamp(Time.now.utc)}",
          date_time_line("DTSTART", start_time),
          date_time_line("DTEND", end_time),
          "SUMMARY:#{escape_text(event.title)}"
        ]
        add_optional_fields(vevent)
        vevent << "END:VEVENT"
        vevent
      end

      # Adds optional fields to the event component if they exist.
      # Handles description, location, URL, geo, organizer, attendees, recurrence,
      # visibility/busy status, and reminders.
      #
      # @param vevent [Array<String>] The current event lines array
      # @return [void]
      def add_optional_fields(vevent)
        description_parts = []
        description_parts << format_description if format_description
        if description_parts.any?
          vevent << "DESCRIPTION:#{escape_text(description_parts.join('\n\n'))}"
        end

        if location = format_location
          vevent << "LOCATION:#{escape_text(location)}"
        end

        if url = format_url
          # URL is a URI value, not TEXT: RFC 5545 escaping would corrupt it.
          vevent << "URL:#{url}"
        end

        vevent << geo_line if geo_line

        if organizer = organizer_line
          vevent << organizer
        end

        attendees_list.each { |attendee| vevent << attendee_line(attendee) }

        vevent << rrule_line if rrule_line
        vevent << sequence_line
        vevent << status_line
        vevent << transp_line
        vevent << busystatus_line
        vevent << class_line
        vevent.concat(importance_lines)
        vevent << disallow_counter_line if disallow_counter_line
        vevent.concat(valarm_lines)
      end

      # Formats a time object as an UTC timestamp in iCalendar format.
      #
      # @param time [Time] The time to format
      # @return [String] The formatted UTC timestamp (YYYYMMDDTHHmmSSZ)
      def format_timestamp(time)
        time.utc.strftime("%Y%m%dT%H%M%SZ")
      end

      # Formats a time object as a date string in iCalendar format.
      #
      # @param time [Time] The time to format
      # @return [String] The formatted date (YYYYMMDD)
      def format_date(time)
        time.strftime("%Y%m%d")
      end

      # Builds a DTSTART/DTEND line: a `Z`-suffixed UTC timestamp for UTC events,
      # otherwise local wall-clock time referencing the event's VTIMEZONE.
      #
      # @param name [String] The property name ("DTSTART" or "DTEND")
      # @param time [Time] The time to format (UTC)
      # @return [String] The content line
      def date_time_line(name, time)
        if CalInvite::IcalTimezone.utc?(event.timezone)
          "#{name}:#{format_timestamp(time)}"
        else
          "#{name};TZID=#{event.timezone}:#{format_local_timestamp(time)}"
        end
      end

      # Formats a time object as a local timestamp in iCalendar format.
      # Converts from UTC to the event's timezone; times are expected to be in
      # UTC already.
      #
      # @param time [Time] The time to format
      # @return [String] The formatted local time (YYYYMMDDTHHmmSS)
      def format_local_timestamp(time)
        local_wall_time(time).strftime("%Y%m%dT%H%M%S")
      end

      # Escapes a TEXT value per RFC 5545 §3.3.11: backslash, semicolon and comma
      # are backslash-escaped, and any line break (CRLF, CR or LF) becomes `\n`.
      #
      # @param text [String, nil] The text to escape
      # @return [String] The escaped text, or empty string if input was nil
      def escape_text(text)
        return '' if text.nil?

        text.to_s.gsub(/\r\n|[\r\n\\;,]/) { |match| match.match?(/[\r\n]/) ? '\\n' : "\\#{match}" }
      end
    end
  end
end
