# frozen_string_literal: true

# test/cal_invite/timezone_test.rb
require 'test_helper'

module CalInvite
  class TimezoneTest < Minitest::Test
    def build_event(attrs = {})
      Event.new({
        title: "Meeting",
        start_time: Time.utc(2026, 11, 1, 15),
        end_time: Time.utc(2026, 11, 1, 16)
      }.merge(attrs))
    end

    def test_unknown_timezones_are_rejected
      ["Mars/Base", "+01:00", "EST5EDT;VALUE=DATE", "America/New_York:X", ""].each do |tz|
        error = assert_raises(ArgumentError, tz.inspect) { build_event(timezone: tz) }
        assert_match(/Unknown timezone/, error.message)
      end
    end

    def test_update_attributes_rejects_unknown_timezone
      event = build_event
      assert_raises(ArgumentError) { event.update_attributes(timezone: "Nowhere/City") }
    end

    def test_iana_timezones_are_accepted
      %w[America/New_York Europe/Paris Asia/Kolkata Etc/UTC].each do |tz|
        assert_equal tz, build_event(timezone: tz).timezone
      end
    end

    def test_utc_emits_z_timestamps_without_tzid_or_vtimezone
      %w[UTC utc].each do |tz|
        ics = build_event(timezone: tz).generate_calendar_url(:ics)
        assert_includes ics, "DTSTART:20261101T150000Z\r\n"
        assert_includes ics, "DTEND:20261101T160000Z\r\n"
        refute_includes ics, "TZID"
        refute_includes ics, "VTIMEZONE"
      end
    end

    def test_default_timezone_is_utc
      ics = build_event.generate_calendar_url(:ics)
      assert_includes ics, "DTSTART:20261101T150000Z\r\n"
    end

    def test_every_tzid_has_a_matching_vtimezone
      ics = build_event(timezone: "Europe/Paris").generate_calendar_url(:ics)
      assert_includes ics, "DTSTART;TZID=Europe/Paris:20261101T160000\r\n"
      assert_includes ics, "BEGIN:VTIMEZONE\r\nTZID:Europe/Paris\r\n"
    end
  end
end
