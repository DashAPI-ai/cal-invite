# frozen_string_literal: true

# test/cal_invite/ics_folding_test.rb
require 'test_helper'

module CalInvite
  # RFC 5545 §3.1: content lines longer than 75 octets must be folded with
  # CRLF followed by a single space.
  class IcsFoldingTest < Minitest::Test
    def build_event(attrs = {})
      Event.new({
        title: "Meeting",
        start_time: Time.utc(2026, 11, 1, 15),
        end_time: Time.utc(2026, 11, 1, 16)
      }.merge(attrs))
    end

    def physical_lines(ics)
      ics.split("\r\n")
    end

    def unfold(ics)
      ics.gsub("\r\n ", "")
    end

    def test_every_line_is_at_most_75_octets
      ics = build_event(
        description: "x" * 300,
        attendees: [{ email: "someone.with.a.long.address@example.com", name: "A Rather Long Display Name" }],
        show_attendees: true
      ).generate_calendar_url(:ics)

      assert physical_lines(ics).all? { |line| line.bytesize <= 75 }, physical_lines(ics).max_by(&:bytesize)
    end

    def test_folded_lines_unfold_to_the_original_value
      description = "Agenda: " + ("lorem ipsum dolor sit amet " * 10).strip
      ics = build_event(description: description).generate_calendar_url(:ics)

      assert_includes unfold(ics).split("\r\n"), "DESCRIPTION:#{description}"
      continuation = physical_lines(ics).drop_while { |l| !l.start_with?("DESCRIPTION:") }[1]
      assert continuation.start_with?(" "), "continuation line must start with a single space"
    end

    def test_folding_never_splits_multibyte_characters
      description = "日本語のテキスト😀" * 20
      ics = build_event(description: description).generate_calendar_url(:ics)

      physical_lines(ics).each do |line|
        assert line.valid_encoding?, "split inside a UTF-8 character: #{line.inspect}"
        assert line.bytesize <= 75
      end
      assert_includes unfold(ics).split("\r\n"), "DESCRIPTION:#{description}"
    end

    def test_short_lines_are_untouched
      ics = build_event(title: "Short").generate_calendar_url(:ics)
      assert_includes physical_lines(ics), "SUMMARY:Short"
      refute physical_lines(ics).any? { |l| l.start_with?(" ") }
    end

    def test_line_of_exactly_75_octets_is_not_folded
      title = "x" * (75 - "SUMMARY:".bytesize)
      ics = build_event(title: title).generate_calendar_url(:ics)
      assert_includes physical_lines(ics), "SUMMARY:#{title}"
    end

    def test_ical_and_ics_content_are_folded_too
      event = build_event(description: "y" * 200)
      [event.generate_calendar_url(:ical), Providers::IcsContent.new(event).generate].each do |ics|
        assert physical_lines(ics).all? { |line| line.bytesize <= 75 }
      end
    end
  end
end
