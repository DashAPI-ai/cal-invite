# frozen_string_literal: true

module CalInvite
  module Providers
    # Base class for calendar providers that implements common functionality
    # and defines the interface that all providers must implement.
    #
    # @abstract Subclass and override {#generate} to implement a calendar provider
    class BaseProvider
      attr_reader :event, :method

      # Initialize a new calendar provider
      #
      # @param event [CalInvite::Event] The event to generate a calendar URL for
      # @param method [Symbol] The iCalendar METHOD (:publish or :request). Only
      #   meaningful to the ics-family providers; URL-based providers ignore it.
      def initialize(event, method: :publish)
        @event = event
        @method = method
      end

      # Generate a calendar URL or content for the event.
      # This method must be implemented by all provider subclasses.
      #
      # @abstract
      # @return [String] The generated calendar URL or content
      # @raise [NotImplementedError] if the provider class doesn't implement this method
      def generate
        raise NotImplementedError, "#{self.class} must implement #generate"
      end

      protected

      # URL encode a string for use in calendar URLs
      #
      # @param str [#to_s] The string to encode
      # @return [String] The URL encoded string
      def url_encode(str)
        URI.encode_www_form_component(str.to_s)
      end

      # Format the event description
      # @return [String, nil] The formatted description or nil if no content
      def format_description
        parts = []
        parts << event.description if event.description
        parts << "Notes: #{event.notes}" if event.notes
        parts.join("\n\n")
      end

      # Get just the physical location
      # @return [String, nil] The location or nil if not present
      def format_location
        event.location
      end

      # Get the URL for virtual meetings
      # @return [String, nil] The URL or nil if not present
      def format_url
        event.url
      end

      # Format description including URL if present
      # @return [String, nil] The formatted description with URL
      def format_description_with_url
        parts = []
        parts << format_description if format_description
        parts << "Virtual Meeting URL: #{format_url}" if format_url
        parts.join("\n\n")
      end

      def add_optional_params(params)
        params[:description] = url_encode(format_description_with_url) if format_description || format_url
        params[:location] = url_encode(format_location) if format_location

        if event.show_attendees && event.attendees&.any?
          params[:attendees] = attendee_emails.join(',')
        end

        params
      end

      # Get the list of attendees if showing attendees is enabled
      # @return [Array<String, Hash>] The list of attendees (email strings or
      #   { email:, name:, partstat: } hashes) or empty array if disabled/none present
      def attendees_list
        return [] unless event.show_attendees && event.attendees&.any?
        event.attendees
      end

      # Plain email addresses for all attendees, regardless of whether they were
      # given as strings or { email:, name:, partstat: } hashes.
      # @return [Array<String>]
      def attendee_emails
        attendees_list.map { |attendee| attendee_email(attendee) }
      end

      # @param attendee [String, Hash] An attendee as given in Event#attendees
      # @return [String] The attendee's email address
      def attendee_email(attendee)
        attendee.is_a?(Hash) ? attendee_hash_value(attendee, :email) : attendee.to_s
      end

      # Reads `key` from an attendee hash, trying both symbol and string keys.
      # Unlike `attendee[:key] || attendee["key"]`, this doesn't misread an
      # explicit `false` value (e.g. `rsvp: false`) as "not set".
      #
      # @param attendee [Hash] An attendee hash
      # @param key [Symbol] The key to read
      # @return [Object, nil]
      def attendee_hash_value(attendee, key)
        return nil unless attendee.is_a?(Hash)
        return attendee[key] if attendee.key?(key)

        attendee[key.to_s]
      end

      NO_RSVP_METHODS = %i[reply counter decline_counter].freeze

      PARTSTAT_VALUES = {
        accepted: "ACCEPTED",
        declined: "DECLINED",
        tentative: "TENTATIVE",
        needs_action: "NEEDS-ACTION",
        delegated: "DELEGATED"
      }.freeze

      # Formats a full ATTENDEE property line for iCalendar output.
      #
      # @param attendee [String, Hash] An email string, or a hash like
      #   { email:, name:, partstat:, rsvp: } for a display name, specific RSVP
      #   status, and/or an explicit RSVP override. `rsvp:` is rarely needed —
      #   e.g. a "registration confirmed" invite where the recipient is already
      #   `partstat: :accepted` and nothing is actually being requested, so
      #   `rsvp: false` suppresses `RSVP=TRUE` even under `method: :request`.
      # @return [String] The formatted ATTENDEE line
      def attendee_line(attendee)
        email = attendee_email(attendee)
        name = attendee_hash_value(attendee, :name)
        partstat_key = attendee_hash_value(attendee, :partstat)
        rsvp_override = attendee_hash_value(attendee, :rsvp)

        cn = name ? ";CN=#{quoted_param(name)}" : ""
        partstat = PARTSTAT_VALUES[partstat_key&.to_sym] || "NEEDS-ACTION"
        # REPLY/COUNTER/DECLINECOUNTER all flow attendee -> organizer; RSVP=TRUE
        # ("please respond") only makes sense on an organizer -> attendee REQUEST.
        rsvp_default = !NO_RSVP_METHODS.include?(method)
        rsvp = (rsvp_override.nil? ? rsvp_default : rsvp_override) ? ";RSVP=TRUE" : ""

        "ATTENDEE;CUTYPE=INDIVIDUAL;ROLE=REQ-PARTICIPANT;PARTSTAT=#{partstat}#{rsvp}#{cn}:mailto:#{email}"
      end

      # Format the ORGANIZER property for iCalendar output. Like attendees, the
      # organizer may be a plain email string or an { email:, name: } hash.
      # @return [String, nil] The formatted ORGANIZER line, or nil if no organizer is set
      def organizer_line
        organizer = event.organizer
        return nil unless organizer

        email = attendee_email(organizer)
        return nil if email.nil? || email.empty?

        name = attendee_hash_value(organizer, :name)
        cn = name ? ";CN=#{quoted_param(name)}" : ""
        "ORGANIZER#{cn}:mailto:#{email}"
      end

      # The value for the calendar-level METHOD property. RFC 5545 spells this
      # method "DECLINECOUNTER" (one word) despite `:decline_counter` reading more
      # naturally as a Ruby symbol.
      # @return [String] e.g. "REQUEST", "DECLINECOUNTER"
      def method_value
        method == :decline_counter ? "DECLINECOUNTER" : method.to_s.upcase
      end

      # The STATUS property, driven by the iCalendar METHOD in use.
      # @return [String] "STATUS:CANCELLED" for :cancel, "STATUS:CONFIRMED" otherwise
      def status_line
        method == :cancel ? "STATUS:CANCELLED" : "STATUS:CONFIRMED"
      end

      # Converts a time to local wall-clock time for the event's timezone, for use in
      # a `DTSTART;TZID=...`/`DTEND;TZID=...` property. Falls back to the time as given
      # (unconverted) when the timezone isn't a TZInfo-recognized identifier (e.g. 'UTC'
      # or a raw offset string), matching each provider's prior behavior for those cases.
      #
      # @param time [Time] The time to convert (interpreted as UTC)
      # @return [Time] The local wall-clock time
      def local_wall_time(time)
        CalInvite::IcalTimezone.local_time(event.timezone, time) || time
      end

      # Builds the VTIMEZONE component lines for the event's timezone, if applicable.
      # @return [Array<String>, nil] iCalendar lines, or nil for UTC/unrecognized timezones
      def vtimezone_lines
        CalInvite::IcalTimezone.vtimezone_lines(event.timezone)
      end

      # Format the GEO property from Event#geo.
      # @return [String, nil] The formatted GEO line, or nil if no geo is set
      # @raise [ArgumentError] if lat/lng aren't numeric
      def geo_line
        return nil unless event.geo

        lat, lng = event.geo.is_a?(Hash) ? [event.geo[:lat] || event.geo["lat"], event.geo[:lng] || event.geo["lng"]] : event.geo
        return nil unless lat && lng

        "GEO:#{Float(lat)};#{Float(lng)}"
      rescue TypeError, ArgumentError
        raise ArgumentError, "geo lat/lng must be numeric (got #{event.geo.inspect})"
      end

      # The SEQUENCE property, from Event#sequence.
      # @return [String] e.g. "SEQUENCE:0"
      # @raise [ArgumentError] if sequence isn't an integer
      def sequence_line
        "SEQUENCE:#{Integer(event.sequence)}"
      rescue TypeError, ArgumentError
        raise ArgumentError, "sequence must be an integer (got #{event.sequence.inspect})"
      end

      # The TRANSP property, from Event#busy (default true).
      # @return [String] "TRANSP:OPAQUE" (busy) or "TRANSP:TRANSPARENT" (free)
      def transp_line
        event.busy == false ? "TRANSP:TRANSPARENT" : "TRANSP:OPAQUE"
      end

      VISIBILITY_VALUES = %w[PUBLIC PRIVATE CONFIDENTIAL].freeze

      # The CLASS property, from Event#visibility (default :public).
      # @return [String] e.g. "CLASS:PUBLIC"
      # @raise [ArgumentError] if visibility isn't :public, :private, or :confidential
      def class_line
        value = (event.visibility || :public).to_s.upcase
        unless VISIBILITY_VALUES.include?(value)
          raise ArgumentError, "visibility must be one of :public, :private, :confidential (got #{event.visibility.inspect})"
        end

        "CLASS:#{value}"
      end

      # Quotes a parameter value (e.g. CN) and escapes it per RFC 6868, so a display
      # name can't close the quoted string and inject parameters, or break the line.
      #
      # @param value [#to_s] The raw parameter value
      # @return [String] The quoted, escaped value
      def quoted_param(value)
        escaped = value.to_s.gsub(/\^|"|\r\n|[\r\n]/) { |match| { '^' => '^^', '"' => "^'" }.fetch(match, '^n') }
        %("#{escaped}")
      end

      # The RRULE property, from Event#rrule, if set.
      # @return [String, nil] e.g. "RRULE:FREQ=WEEKLY;COUNT=5", or nil if no rrule is set
      def rrule_line
        return nil unless event.rrule

        value = event.rrule.to_s
        value.start_with?("RRULE:") ? value : "RRULE:#{value}"
      end

      # Builds VALARM sub-components from Event#reminders (minutes-before-start values).
      # @return [Array<String>] iCalendar lines, one VALARM block per reminder, or [] if none
      def valarm_lines
        return [] unless event.reminders&.any?

        event.reminders.flat_map do |minutes|
          ["BEGIN:VALARM", "TRIGGER:-PT#{minutes.to_i}M", "ACTION:DISPLAY", "DESCRIPTION:Reminder", "END:VALARM"]
        end
      end

      IMPORTANCE_VALUES = { low: ["9", "0"], normal: ["5", "1"], high: ["1", "2"] }.freeze

      # Standard RFC 5545 PRIORITY plus Outlook's non-standard
      # X-MICROSOFT-CDO-IMPORTANCE, from Event#importance (:low/:normal/:high). Safe
      # to always include: RFC 5545 requires unrecognized X- properties be ignored
      # by compliant parsers, so this has no effect outside Outlook.
      # @return [Array<String>] 0, 1, or 2 lines
      def importance_lines
        values = IMPORTANCE_VALUES[event.importance&.to_sym]
        return [] unless values

        priority, importance = values
        ["PRIORITY:#{priority}", "X-MICROSOFT-CDO-IMPORTANCE:#{importance}"]
      end

      # Outlook's non-standard X-MICROSOFT-CDO-BUSYSTATUS, mirroring Event#busy.
      # Included alongside the standard TRANSP property since some Outlook versions
      # honor this one more reliably.
      # @return [String] e.g. "X-MICROSOFT-CDO-BUSYSTATUS:BUSY"
      def busystatus_line
        "X-MICROSOFT-CDO-BUSYSTATUS:#{event.busy == false ? "FREE" : "BUSY"}"
      end

      # Outlook's non-standard X-MICROSOFT-DISALLOW-COUNTER, from Event#allow_counter
      # (default true). Set Event#allow_counter = false to hide Outlook's "Propose
      # New Time" action — the practical lever for "prevent attendee-initiated
      # reschedules" on Outlook specifically; other clients don't expose an
      # equivalent control and ignore this property.
      # @return [String, nil] "X-MICROSOFT-DISALLOW-COUNTER:TRUE", or nil if counters are allowed
      def disallow_counter_line
        return nil if event.allow_counter != false

        "X-MICROSOFT-DISALLOW-COUNTER:TRUE"
      end
    end
  end
end
