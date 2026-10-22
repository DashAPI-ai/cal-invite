# frozen_string_literal: true

require 'digest'

# lib/cal_invite/event.rb
# Represents a calendar event with all its attributes and generation capabilities.
#
# @attr_accessor [String] title The title of the event
# @attr_accessor [Time] start_time The start time of the event
# @attr_accessor [Time] end_time The end time of the event
# @attr_accessor [String] description The description of the event
# @attr_accessor [String] location The location of the event
# @attr_accessor [String] url The URL associated with the event
# @attr_accessor [Array<String, Hash>] attendees Attendees as email strings, or hashes like
#   { email:, name:, partstat: } for a display name and/or a specific RSVP status
#   (:accepted, :declined, :tentative, :needs_action, :delegated)
# @attr_accessor [String] timezone The timezone for the event
# @attr_accessor [Boolean] show_attendees Whether to include attendees in calendar invites
# @attr_accessor [String] notes Additional notes for the event
# @attr_accessor [Array<Hash>] multi_day_sessions Sessions for multi-day events
# @attr_accessor [Boolean] all_day Whether this is an all-day event
# @attr_accessor [Hash] organizer The event organizer, e.g. { name: "Jane Doe", email: "jane@example.com" }
# @attr_accessor [String] uid Stable RFC 5545 UID identifying this event across its lifecycle
# @attr_accessor [Integer] sequence RFC 5545 SEQUENCE number; bump on every REQUEST/CANCEL update
# @attr_accessor [Array<Float>, Hash] geo Location coordinates, e.g. [37.4595, -122.1418] or { lat:, lng: }
# @attr_accessor [Array<Integer>] reminders Minutes-before-start values, one VALARM per entry
# @attr_accessor [Boolean] busy Whether this event should show as busy (true) or free (false) on free/busy lookups
# @attr_accessor [Symbol, String] visibility :public, :private, or :confidential
# @attr_accessor [String] rrule A raw RFC 5545 recurrence rule value, e.g. "FREQ=WEEKLY;COUNT=5"
# @attr_accessor [String] calendar_name Calendar-level display name (X-WR-CALNAME)
# @attr_accessor [Symbol, String] importance :low, :normal, or :high — maps to the standard
#   PRIORITY property and, for Outlook specifically, X-MICROSOFT-CDO-IMPORTANCE
# @attr_accessor [Boolean] allow_counter Whether attendees may propose a new time. When set to
#   false, emits X-MICROSOFT-DISALLOW-COUNTER — the one client-specific lever available for
#   this; other clients don't expose an equivalent control
module CalInvite
  class Event
    attr_accessor :title,
                  :start_time,
                  :end_time,
                  :description,
                  :location,
                  :url,
                  :attendees,
                  :timezone,
                  :show_attendees,
                  :notes,
                  :multi_day_sessions,
                  :all_day,
                  :organizer,
                  :uid,
                  :sequence,
                  :geo,
                  :reminders,
                  :busy,
                  :visibility,
                  :rrule,
                  :calendar_name,
                  :importance,
                  :allow_counter

    # Initializes a new Event instance with the given attributes.
    #
    # @param attributes [Hash] The attributes to initialize the event with
    # @option attributes [String] :title The event title
    # @option attributes [Time] :start_time The event start time
    # @option attributes [Time] :end_time The event end time
    # @option attributes [String] :description The event description
    # @option attributes [String] :location The event location
    # @option attributes [String] :url The event URL
    # @option attributes [Array<String>] :attendees The event attendees
    # @option attributes [String] :timezone ('UTC') The event timezone
    # @option attributes [Boolean] :show_attendees (false) Whether to show attendees
    # @option attributes [String] :notes Additional notes
    # @option attributes [Array<Hash>] :multi_day_sessions Multi-day session details
    # @option attributes [Boolean] :all_day (false) Whether it's an all-day event
    # @option attributes [Hash] :organizer The event organizer, e.g. { name: "Jane Doe", email: "jane@example.com" }
    # @option attributes [String] :uid A stable identifier for this event. If omitted, a random one
    #   is generated and memoized on this instance. To update or cancel a previously sent invite,
    #   you MUST pass the same :uid used originally — mail/calendar clients match REQUEST/CANCEL
    #   messages to an existing event by UID, not by content.
    # @option attributes [Integer] :sequence (0) RFC 5545 SEQUENCE number. Increment it yourself
    #   each time you re-send a REQUEST or a CANCEL for the same :uid.
    # @option attributes [Array<Float>, Hash] :geo Location coordinates, e.g. [37.4595, -122.1418]
    #   or { lat:, lng: }
    # @option attributes [Array<Integer>] :reminders Minutes-before-start values; one VALARM per entry
    # @option attributes [Boolean] :busy (true) Whether this event shows as busy on free/busy lookups
    # @option attributes [Symbol, String] :visibility (:public) :public, :private, or :confidential
    # @option attributes [String] :rrule A raw RFC 5545 recurrence rule value, e.g. "FREQ=WEEKLY;COUNT=5"
    # @option attributes [String] :calendar_name Calendar-level display name (X-WR-CALNAME)
    # @option attributes [Symbol, String] :importance :low, :normal, or :high
    # @option attributes [Boolean] :allow_counter (true) false emits X-MICROSOFT-DISALLOW-COUNTER
    #
    # @raise [ArgumentError] If required attributes are missing
    def initialize(attributes = {})
      attributes = attributes.dup # never mutate the caller's hash
      @show_attendees = attributes.delete(:show_attendees) || false
      @timezone = attributes.delete(:timezone) || 'UTC'
      @multi_day_sessions = attributes.delete(:multi_day_sessions) || []
      @all_day = attributes.delete(:all_day) || false
      @uid = attributes.delete(:uid) || generate_uid
      @sequence = attributes.delete(:sequence) || 0
      @busy = attributes.key?(:busy) ? attributes.delete(:busy) : true
      @visibility = attributes.delete(:visibility) || :public
      @allow_counter = attributes.key?(:allow_counter) ? attributes.delete(:allow_counter) : true

      attributes.each do |key, value|
        send("#{key}=", value) if respond_to?("#{key}=")
      end

      validate!
    end

    # Generates a calendar URL (or, for the ics/ical/ics_content providers, raw
    # iCalendar content) for the specified provider.
    #
    # @param provider [Symbol] The calendar provider to generate the URL for
    # @param method [Symbol] The iCalendar METHOD to use (:publish, :request, :cancel,
    #   :reply, :counter, or :decline_counter). Only honored by the ics-family providers
    #   (ics, ical, ics_content); ignored by URL-based providers.
    #   - :request (with an {#organizer} set) produces an invite that mail clients
    #     (Gmail, Outlook, Apple Mail) recognize and render with Accept/Decline
    #     actions rather than as a plain attachment.
    #   - :cancel produces a cancellation (STATUS:CANCELLED) for a previously sent
    #     :request. Reuse the same {#uid} and bump {#sequence} so clients match it
    #     to the original invite instead of creating a new event.
    #   - :reply carries an attendee's own PARTSTAT back to the organizer.
    #   - :counter carries an attendee's proposed new {#start_time}/{#end_time} back
    #     to the organizer, keeping the original {#uid}/{#sequence}. Client support for
    #     rendering this as an actionable UI is inconsistent — see CONFIGURATION.md's
    #     "Attendee-proposed reschedules (COUNTER)".
    #   - :decline_counter is the organizer rejecting a :counter proposal.
    # @return [String] The generated calendar URL or content
    # @raise [ArgumentError] If required event attributes are missing
    #
    # @example Generate a Google Calendar URL
    #   event.generate_calendar_url(:google)
    #
    # @example Generate an Outlook Calendar URL
    #   event.generate_calendar_url(:outlook)
    #
    # @example Generate an RFC 5545 meeting request for emailing as an invite
    #   event.organizer = { name: "Jane Doe", email: "jane@example.com" }
    #   event.generate_calendar_url(:ics, method: :request)
    #
    # @example Cancel a previously sent invite
    #   event.uid = "the-original-uid@cal-invite"  # must match the original REQUEST
    #   event.sequence = 1                          # incremented from the original
    #   event.generate_calendar_url(:ics, method: :cancel)
    def generate_calendar_url(provider, method: :publish)
      validate!

      if caching_enabled?
        cache_key = cache_key_for(provider, method)
        cached_url = fetch_from_cache(cache_key)
        return cached_url if cached_url
      end

      # Generate the URL
      provider_class = CalInvite::Providers.const_get(capitalize_provider(provider.to_s))
      generator = provider_class.new(self, method: method)
      url = generator.generate

      # Cache the result if caching is enabled
      write_to_cache(cache_key, url) if caching_enabled?

      url
    end

    # Updates the event attributes with new values.
    #
    # @param new_attributes [Hash] The new attributes to update
    # @return [void]
    # @raise [ArgumentError] If the updated attributes make the event invalid
    #
    # @example Update event title and time
    #   event.update_attributes(
    #     title: "Updated Meeting",
    #     start_time: Time.now + 3600
    #   )
    def update_attributes(new_attributes)
      new_attributes.each do |key, value|
        send("#{key}=", value) if respond_to?("#{key}=")
      end

      invalidate_cache if caching_enabled?
      validate!
    end

    private

    # Generates a stable unique identifier for this event.
    # Format: timestamp-randomhex@cal-invite
    #
    # @return [String] The generated UID
    def generate_uid
      "#{Time.now.to_i}-#{SecureRandom.hex(8)}@cal-invite"
    end

    # Capitalizes each part of the provider name.
    #
    # @param string [String] The provider name to capitalize
    # @return [String] The capitalized provider name
    # @example
    #   capitalize_provider('google_calendar') # => "GoogleCalendar"
    def capitalize_provider(string)
      string.split('_').map(&:capitalize).join
    end

    # Validates the event attributes.
    #
    # @raise [ArgumentError] If required attributes are missing or invalid
    def validate!
      raise ArgumentError, "Title is required" if title.nil? || title.strip.empty?

      unless all_day
        raise ArgumentError, "Start time is required for non-all-day events" if start_time.nil?
        raise ArgumentError, "End time is required for non-all-day events" if end_time.nil?
      end

      validate_time_order!(start_time, end_time, "End time")
      multi_day_sessions.each_with_index do |session, index|
        label = "Session #{index + 1}"
        raise ArgumentError, "#{label} requires start_time and end_time" unless session[:start_time] && session[:end_time]

        validate_time_order!(session[:start_time], session[:end_time], "#{label} end_time")
      end

      unless CalInvite::IcalTimezone.valid?(timezone)
        raise ArgumentError, "Unknown timezone #{timezone.inspect}: use 'UTC' or an IANA identifier such as 'America/New_York'"
      end
    end

    # Raises unless the end comes after the start. RFC 5545 requires DTEND to be
    # later than DTSTART; all-day events may start and end on the same date.
    #
    # @param start_at [Time, Date, nil] The start
    # @param end_at [Time, Date, nil] The end
    # @param label [String] What to call the end in the error message
    # @raise [ArgumentError] If the end is before (or, for timed events, equal to) the start
    def validate_time_order!(start_at, end_at, label)
      return unless start_at && end_at
      return if end_at > start_at || (all_day && end_at == start_at)

      raise ArgumentError, "#{label} must be after start time"
    end

    # Checks if caching is enabled in the configuration.
    #
    # @return [Boolean] true if caching is enabled, false otherwise
    def caching_enabled?
      CalInvite.configuration &&
        CalInvite.configuration.respond_to?(:cache_store) &&
        CalInvite.configuration.cache_store
    end

    # Generates a cache key for the event and provider combination.
    #
    # @param provider [Symbol] The calendar provider
    # @param method [Symbol] The iCalendar METHOD used to generate the content
    # @return [String, nil] The cache key or nil if caching is disabled
    def cache_key_for(provider, method = :publish)
      return nil unless caching_enabled?

      attributes_hash = Digest::MD5.hexdigest(
        [
          title,
          start_time&.to_i,
          end_time&.to_i,
          description,
          location,
          url,
          attendees,
          timezone,
          show_attendees,
          notes,
          multi_day_sessions,
          all_day,
          organizer,
          uid,
          sequence,
          geo,
          reminders,
          busy,
          visibility,
          rrule,
          calendar_name,
          importance,
          allow_counter,
          provider,
          method
        ].map(&:to_s).join('|')
      )

      "cal_invite:event:#{attributes_hash}"
    end

    # Retrieves a value from the cache store.
    #
    # @param key [String] The cache key
    # @return [String, nil] The cached value or nil if not found
    def fetch_from_cache(key)
      return nil unless key && caching_enabled?
      CalInvite.configuration.cache_store.read(key)
    end

    # Writes a value to the cache store.
    #
    # @param key [String] The cache key
    # @param value [String] The value to cache
    # @return [void]
    def write_to_cache(key, value)
      return unless key && caching_enabled?

      expires_in = CalInvite.configuration&.cache_expires_in
      CalInvite.configuration.cache_store.write(
        key,
        value,
        expires_in: expires_in
      )
    end

    # Invalidates all cached URLs for this event.
    #
    # @return [void]
    def invalidate_cache
      return unless caching_enabled?

      if CalInvite.configuration.cache_store.respond_to?(:delete_matched)
        CalInvite.configuration.cache_store.delete_matched("cal_invite:event:*")
      end
    end
  end
end
