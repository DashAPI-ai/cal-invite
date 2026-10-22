# test/cal_invite/providers_test.rb
require 'test_helper'

module CalInvite
  class ProvidersTest < Minitest::Test
    def setup
      # Explicitly set UTC time using Time.utc to avoid timezone confusion
      @start_time = Time.utc(2024, 1, 1, 9, 0, 0)  # 9 AM UTC
      @end_time = Time.utc(2024, 1, 1, 10, 0, 0)   # 10 AM UTC
      @event = Event.new(
        title: "Test Meeting",
        start_time: @start_time,
        end_time: @end_time,
        description: "Test Description",
        location: "Test Location",
        url: "https://meet.test.com",
        attendees: ["test@example.com"],
        timezone: "UTC"
      )
    end

    def test_timezone_handling
      # Test with a non-UTC display timezone
      event = Event.new(
        title: "Test Meeting",
        start_time: Time.new(2024, 1, 1, 9, 0, 0, "+00:00"),
        end_time: Time.new(2024, 1, 1, 10, 0, 0, "+00:00"),
        timezone: "Europe/Paris"
      )

      url = event.generate_calendar_url(:google)
      # Google Calendar expects UTC times, with the display zone in ctz
      assert_match %r{dates=20240101T090000Z/20240101T100000Z}, url
      assert_match %r{ctz=Europe%2FParis}, url
    end

    def test_google_calendar_url
      url = @event.generate_calendar_url(:google)
      assert_match %r{^https://calendar\.google\.com/calendar/render\?action=TEMPLATE}, url
      assert_match %r{&text=Test\+Meeting}, url
      assert_match %r{&dates=20240101T090000Z/20240101T100000Z}, url
      assert_match %r{&location=Test\+Location}, url
    end

    def test_outlook_calendar_url
      url = @event.generate_calendar_url(:outlook)
      assert_match %r{^https://outlook\.live\.com/calendar/deeplink/compose\?}, url
      assert_match %r{path=/calendar/action/compose}, url
      assert_match %r{rru=addevent}, url
      assert_match %r{&subject=Test\+Meeting}, url
      assert_match %r{&startdt=2024-01-01T09:00:00Z}, url
      assert_match %r{&enddt=2024-01-01T10:00:00Z}, url
    end

    def test_office365_calendar_url
      url = @event.generate_calendar_url(:office365)
      assert_match %r{^https://outlook\.office\.com/calendar/deeplink/compose\?}, url
      assert_match %r{rru=addevent}, url
      assert_match %r{subject=Test\+Meeting}, url  # Removed the & prefix since it could be anywhere in the query string
      assert_match %r{startdt=2024-01-01T09%3A00%3A00Z}, url
      assert_match %r{enddt=2024-01-01T10%3A00%3A00Z}, url
      # Optional but recommended assertions
      assert_match %r{path=/calendar/action/compose}, url
      assert_match %r{body=}, url
      assert_match %r{location=}, url
    end

    def test_google_calendar_url_optional_params
      event = Event.new(
        title: "Test Meeting",
        start_time: @start_time,
        end_time: @end_time,
        timezone: "America/New_York",
        attendees: ["alice@example.com", "bob@example.com"],
        show_attendees: true,
        rrule: "FREQ=WEEKLY;COUNT=5",
        busy: true
      )

      url = event.generate_calendar_url(:google)
      assert_match %r{ctz=America%2FNew_York}, url
      assert_match %r{add=alice%40example\.com%2Cbob%40example\.com}, url
      assert_match %r{recur=RRULE%3AFREQ%3DWEEKLY%3BCOUNT%3D5}, url
      assert_match %r{crm=BUSY}, url
    end

    def test_outlook_and_office365_freebusy_param
      event = Event.new(
        title: "Test Meeting",
        start_time: @start_time,
        end_time: @end_time,
        busy: false
      )

      assert_match %r{freebusy=free}, event.generate_calendar_url(:outlook)
      assert_match %r{freebusy=free}, event.generate_calendar_url(:office365)
    end

    def test_yahoo_calendar_url
      url = @event.generate_calendar_url(:yahoo)
      assert_match %r{^https://calendar\.yahoo\.com/}, url
      assert_match %r{&title=Test\+Meeting}, url
      assert_match %r{&st=20240101T090000Z}, url
      assert_match %r{&et=20240101T100000Z}, url
    end

    def test_ical_calendar_url
      # For iCal, we expect to get ICS content
      content = @event.generate_calendar_url(:ical)
      assert_match %r{BEGIN:VCALENDAR}, content
      assert_match %r{VERSION:2\.0}, content
      assert_match %r{DTSTART:20240101T090000Z}, content
      assert_match %r{DTEND:20240101T100000Z}, content
      refute_match %r{TZID=}, content
      assert_match %r{SUMMARY:Test Meeting}, content
      assert_match %r{LOCATION:Test Location}, content
      assert_match %r{URL:https://meet.test.com}, content
    end

    def test_url_encoding_special_characters
      event = Event.new(
        title: "Test & Meeting + Spaces",
        start_time: @start_time,
        end_time: @end_time,
        location: "Location & More",
        timezone: "UTC"
      )

      url = event.generate_calendar_url(:google)
      assert_match %r{text=Test\+%26\+Meeting\+%2B\+Spaces}, url
      assert_match %r{location=Location\+%26\+More}, url
    end

    def test_all_day_event_formatting
      event = Event.new(
        title: "All Day Event",
        all_day: true
      )

      # Test Google calendar formatting
      google_url = event.generate_calendar_url(:google)
      today = Time.now.strftime('%Y%m%d')
      tomorrow = (Time.now + 86400).strftime('%Y%m%d')
      assert_match %r{dates=#{today}/#{tomorrow}}, google_url

      # Test other providers
      [:outlook, :office365, :yahoo, :ical].each do |provider|
        result = event.generate_calendar_url(provider)
        assert result, "URL/content should be generated for #{provider} with all-day event"
      end
    end

    def test_all_day_event_with_specific_dates
      event = Event.new(
        title: "All Day Event",
        all_day: true,
        start_time: Time.new(2024, 1, 1),
        end_time: Time.new(2024, 1, 2)
      )

      url = event.generate_calendar_url(:google)
      assert_match %r{dates=20240101/20240102}, url
    end

    def test_separate_location_and_url
      event = Event.new(
        title: "Hybrid Meeting",
        start_time: @start_time,
        end_time: @end_time,
        location: "Conference Room A",
        url: "https://meet.test.com",
        timezone: "UTC"
      )

      # Test Google Calendar
      google_url = event.generate_calendar_url(:google)
      assert_match %r{location=Conference\+Room\+A}, google_url
      assert_match %r{details=.*https%3A%2F%2Fmeet\.test\.com}, google_url

      # Test ICS generation
      ics_content = event.generate_calendar_url(:ics)
      assert_match %r{LOCATION:Conference Room A}, ics_content
      assert_match %r{URL:https://meet.test.com}, ics_content
    end

    def test_ics_non_utc_timezone_converts_to_local_time_with_vtimezone
      event = Event.new(
        title: "NY Meeting",
        start_time: Time.utc(2026, 11, 1, 15, 0, 0),
        end_time: Time.utc(2026, 11, 1, 16, 0, 0),
        timezone: "America/New_York"
      )
      ics = event.generate_calendar_url(:ics)

      assert_includes ics, "DTSTART;TZID=America/New_York:20261101T100000"
      assert_includes ics, "DTEND;TZID=America/New_York:20261101T110000"
      assert_includes ics, "BEGIN:VTIMEZONE\r\nTZID:America/New_York"
      assert_includes ics, "TZOFFSETFROM:-0400\r\nTZOFFSETTO:-0500\r\nTZNAME:EST"
      assert_includes ics, "TZOFFSETFROM:-0500\r\nTZOFFSETTO:-0400\r\nTZNAME:EDT"
    end

    def test_ics_family_providers_produce_identical_content
      event = Event.new(
        title: "Sync",
        start_time: @start_time,
        end_time: @end_time,
        timezone: "America/New_York",
        organizer: { email: "org@example.com", name: "Org" },
        attendees: ["test@example.com"],
        show_attendees: true,
        description: "Agenda",
        notes: "Bring laptop"
      )
      strip_dtstamp = ->(ics) { ics.gsub(/^DTSTAMP:.*$/, "") }
      expected = strip_dtstamp.call(Providers::Ics.new(event, method: :request).generate)

      assert_includes expected, "BEGIN:VTIMEZONE"
      assert_includes expected, "METHOD:REQUEST"
      [Providers::Ical, Providers::IcsContent].each do |klass|
        assert_equal expected, strip_dtstamp.call(klass.new(event, method: :request).generate), klass.name
      end
    end

    def test_ics_family_all_day_event_without_times
      event = Event.new(title: "Holiday", all_day: true)
      today = Time.now.strftime("%Y%m%d")

      [:ics, :ical].each do |provider|
        assert_match %r{DTSTART;VALUE=DATE:#{today}}, event.generate_calendar_url(provider)
      end
    end

    def test_unsupported_provider_raises_a_clear_error
      [:string, :base_provider, :ics_download, "nope"].each do |provider|
        error = assert_raises(ArgumentError, provider.inspect) { @event.generate_calendar_url(provider) }
        assert_equal "Unsupported provider #{provider.inspect}; supported: google, ical, outlook, yahoo, ics, office365", error.message
      end
    end

    def test_every_supported_provider_resolves
      Providers::SUPPORTED_PROVIDERS.each do |provider|
        refute_empty @event.generate_calendar_url(provider), provider.inspect
        refute_empty @event.generate_calendar_url(provider.to_s), provider.to_s
      end
    end

    def test_ics_content_is_a_legacy_alias_of_ics
      strip_dtstamp = ->(ics) { ics.gsub(/^DTSTAMP:.*$/, "") }
      assert_equal strip_dtstamp.call(@event.generate_calendar_url(:ics)),
                   strip_dtstamp.call(@event.generate_calendar_url(:ics_content))
    end
  end
end
