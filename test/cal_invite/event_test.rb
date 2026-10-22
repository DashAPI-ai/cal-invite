# test/cal_invite/event_test.rb
require 'test_helper'

module CalInvite
  class EventTest < Minitest::Test
    def test_requires_title
      error = assert_raises(ArgumentError) do
        Event.new(
          start_time: Time.now,
          end_time: Time.now + 3600  # 1 hour in seconds
        )
      end
      assert_equal "Title is required", error.message
    end

    def test_requires_start_time_for_non_all_day_events
      error = assert_raises(ArgumentError) do
        Event.new(
          title: "Meeting",
          end_time: Time.now + 3600  # 1 hour in seconds
        )
      end
      assert_equal "Start time is required for non-all-day events", error.message
    end

    def test_requires_end_time_for_non_all_day_events
      error = assert_raises(ArgumentError) do
        Event.new(
          title: "Meeting",
          start_time: Time.now
        )
      end
      assert_equal "End time is required for non-all-day events", error.message
    end

    def test_does_not_require_times_for_all_day_events
      event = Event.new(
        title: "All Day Meeting",
        all_day: true
      )
      assert event
      assert event.all_day
    end

    def test_show_attendees_defaults_to_false
      event = Event.new(title: "Meeting", all_day: true)
      refute event.show_attendees
    end

    def test_all_day_defaults_to_false
      start_time = Time.now
      event = Event.new(
        title: "Meeting",
        start_time: start_time,
        end_time: start_time + 3600  # 1 hour in seconds
      )
      refute event.all_day
    end

    def test_does_not_mutate_the_callers_attributes_hash
      attributes = {
        title: "Meeting",
        start_time: Time.utc(2026, 11, 1, 15),
        end_time: Time.utc(2026, 11, 1, 16),
        timezone: "Europe/Paris",
        show_attendees: true,
        uid: "fixed-uid",
        sequence: 2,
        busy: false,
        visibility: :private,
        allow_counter: false
      }
      snapshot = attributes.dup

      first = Event.new(attributes)
      second = Event.new(attributes)

      assert_equal snapshot, attributes
      [first, second].each do |event|
        assert_equal "Europe/Paris", event.timezone
        assert_equal "fixed-uid", event.uid
        assert_equal 2, event.sequence
        assert_equal false, event.busy
        assert_equal false, event.allow_counter
      end
    end

    def test_rejects_end_time_before_or_equal_to_start_time
      start = Time.utc(2026, 11, 1, 15)
      [start - 3600, start].each do |end_time|
        error = assert_raises(ArgumentError) { Event.new(title: "Meeting", start_time: start, end_time: end_time) }
        assert_equal "End time must be after start time", error.message
      end
    end

    def test_update_attributes_rejects_end_time_before_start_time
      event = Event.new(title: "Meeting", start_time: Time.utc(2026, 11, 1, 15), end_time: Time.utc(2026, 11, 1, 16))
      assert_raises(ArgumentError) { event.update_attributes(end_time: Time.utc(2026, 11, 1, 14)) }
    end

    def test_all_day_event_may_start_and_end_on_the_same_date
      event = Event.new(title: "Holiday", all_day: true, start_time: Date.new(2026, 12, 25), end_time: Date.new(2026, 12, 25))
      assert event.all_day
      assert_raises(ArgumentError) do
        Event.new(title: "Holiday", all_day: true, start_time: Date.new(2026, 12, 25), end_time: Date.new(2026, 12, 24))
      end
    end

    def test_multi_day_sessions_must_be_complete_and_ordered
      base = { title: "Workshop", start_time: Time.utc(2026, 3, 1, 8), end_time: Time.utc(2026, 3, 2, 13) }
      good = { start_time: Time.utc(2026, 3, 1, 8), end_time: Time.utc(2026, 3, 1, 17) }

      error = assert_raises(ArgumentError) do
        Event.new(base.merge(multi_day_sessions: [good, { start_time: Time.utc(2026, 3, 2, 13), end_time: Time.utc(2026, 3, 2, 9) }]))
      end
      assert_equal "Session 2 end_time must be after start time", error.message

      error = assert_raises(ArgumentError) do
        Event.new(base.merge(multi_day_sessions: [{ start_time: Time.utc(2026, 3, 1, 8) }]))
      end
      assert_equal "Session 1 requires start_time and end_time", error.message

      assert_equal 1, Event.new(base.merge(multi_day_sessions: [good])).multi_day_sessions.size
    end

    def test_rejects_unknown_attributes
      error = assert_raises(ArgumentError) do
        Event.new(title: "Meeting", start_time: Time.utc(2026, 11, 1, 15), end_time: Time.utc(2026, 11, 1, 16), locaton: "Paris", "colour" => "red")
      end
      assert_equal "Unknown attribute(s): locaton, colour", error.message
    end

    def test_update_attributes_rejects_unknown_attributes_without_changing_anything
      event = Event.new(title: "Meeting", start_time: Time.utc(2026, 11, 1, 15), end_time: Time.utc(2026, 11, 1, 16))

      error = assert_raises(ArgumentError) { event.update_attributes(title: "Renamed", locaton: "Paris") }
      assert_equal "Unknown attribute(s): locaton", error.message
      assert_equal "Meeting", event.title
    end

    def test_accepts_string_keyed_attributes
      event = Event.new(
        "title" => "Meeting",
        "start_time" => Time.utc(2026, 11, 1, 15),
        "end_time" => Time.utc(2026, 11, 1, 16),
        "timezone" => "Europe/Paris",
        "busy" => false,
        "uid" => "string-uid"
      )

      assert_equal "Europe/Paris", event.timezone
      assert_equal false, event.busy
      assert_equal "string-uid", event.uid
    end

    def build_multi_day_event(attrs = {})
      Event.new({
        title: "Training Workshop",
        multi_day_sessions: [
          { start_time: Time.parse("2024-03-02 09:00:00 UTC"), end_time: Time.parse("2024-03-02 13:00:00 UTC") },
          { start_time: Time.parse("2024-03-01 08:00:00 UTC"), end_time: Time.parse("2024-03-01 17:00:00 UTC") }
        ],
        timezone: "America/New_York"
      }.merge(attrs))
    end

    def test_multi_day_event_without_top_level_times_spans_its_sessions
      event = build_multi_day_event

      assert_equal Time.parse("2024-03-01 08:00:00 UTC"), event.start_time
      assert_equal Time.parse("2024-03-02 13:00:00 UTC"), event.end_time
      Providers::SUPPORTED_PROVIDERS.each do |provider|
        refute_empty event.generate_calendar_url(provider), provider
      end
      assert_includes event.generate_calendar_url(:google), "dates=20240301T080000Z/20240302T130000Z"
      assert_equal 2, event.generate_calendar_url(:ics).scan("BEGIN:VEVENT").size
      assert_equal 2, event.generate_calendar_url(:yahoo).lines.size
    end

    def test_explicit_times_win_over_multi_day_span
      start_time = Time.parse("2024-02-28 10:00:00 UTC")
      end_time = Time.parse("2024-03-03 10:00:00 UTC")
      event = build_multi_day_event(start_time: start_time, end_time: end_time)

      assert_equal start_time, event.start_time
      assert_equal end_time, event.end_time
    end

    def test_multi_day_span_follows_updated_sessions
      event = build_multi_day_event
      later = Time.parse("2024-03-05 09:00:00 UTC")
      event.update_attributes(multi_day_sessions: [{ start_time: later, end_time: later + 3600 }])

      assert_equal later, event.start_time
      assert_equal later + 3600, event.end_time
    end

    def test_times_still_required_without_sessions
      assert_raises(ArgumentError) { Event.new(title: "T", multi_day_sessions: []) }
    end
  end
end
