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
  end
end
