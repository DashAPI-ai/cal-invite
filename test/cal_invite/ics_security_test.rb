# frozen_string_literal: true

# test/cal_invite/ics_security_test.rb
require 'test_helper'

module CalInvite
  # Untrusted strings must never be able to break out of their content line
  # (or their quoted parameter) and inject properties into generated .ics files.
  class IcsSecurityTest < Minitest::Test
    INJECTION = "\r\nATTENDEE:mailto:attacker@evil.com\r\nX-INJECTED:1"

    def build_event(attrs = {})
      Event.new({
        title: "Meeting",
        start_time: Time.utc(2026, 11, 1, 15),
        end_time: Time.utc(2026, 11, 1, 16),
        show_attendees: true
      }.merge(attrs))
    end

    # Unfolds (RFC 5545 §3.1) before splitting, as a calendar client would.
    def content_lines(ics)
      ics.gsub("\r\n ", "").split("\r\n")
    end

    def assert_no_injection(ics)
      lines = content_lines(ics)
      refute lines.any? { |l| l.start_with?("X-INJECTED", "ATTENDEE:mailto:attacker") }, "injected line found:\n#{ics}"
      refute lines.any? { |l| l.match?(/[\r\n]/) }, "bare CR/LF inside a content line"
    end

    # --- TEXT values are escaped, never rejected ---

    def test_text_fields_escape_line_breaks
      %i[title description location notes calendar_name].each do |field|
        ics = build_event(field => "x#{INJECTION}").generate_calendar_url(:ics)
        assert_no_injection(ics)
      end
    end

    def test_lone_carriage_return_in_title_is_escaped
      ics = build_event(title: "Hi\rMETHOD:CANCEL").generate_calendar_url(:ics)
      assert_no_injection(ics)
      assert_includes content_lines(ics), "SUMMARY:Hi\\nMETHOD:CANCEL"
      assert_equal 1, content_lines(ics).count { |l| l.start_with?("METHOD:") }
    end

    def test_escape_text_follows_rfc5545
      ics = build_event(description: "C:\\path; a, b\r\nnext\rline\nend").generate_calendar_url(:ics)
      assert_includes content_lines(ics), "DESCRIPTION:C:\\\\path\\; a\\, b\\nnext\\nline\\nend"
    end

    # --- Parameter values (CN) are quoted and RFC 6868-escaped ---

    def test_attendee_name_cannot_inject_lines_or_parameters
      ics = build_event(
        attendees: [{ email: "a@example.com", name: %(Bob";ROLE=CHAIR#{INJECTION}) }]
      ).generate_calendar_url(:ics)

      assert_no_injection(ics)
      attendee = content_lines(ics).find { |l| l.start_with?("ATTENDEE") }
      assert_includes attendee, %(;CN="Bob^';ROLE=CHAIR^nATTENDEE:mailto:attacker@evil.com^nX-INJECTED:1":mailto:a@example.com)
    end

    def test_organizer_name_cannot_inject
      ics = build_event(organizer: { email: "o@example.com", name: "O^\"#{INJECTION}" }).generate_calendar_url(:ics)
      assert_no_injection(ics)
      assert_includes content_lines(ics).find { |l| l.start_with?("ORGANIZER") }, %(CN="O^^^'^nATTENDEE)
    end

    def test_plain_names_are_quoted_unchanged
      ics = build_event(attendees: [{ email: "a@example.com", name: "Ada Lovelace" }]).generate_calendar_url(:ics)
      assert_match(/;CN="Ada Lovelace":mailto:a@example.com\z/, content_lines(ics).find { |l| l.start_with?("ATTENDEE") })
    end

    # --- Non-TEXT values with line breaks are rejected ---

    def test_unescapable_values_with_line_breaks_raise
      cases = {
        "ATTENDEE" => { attendees: ["a@example.com#{INJECTION}"] },
        "ORGANIZER" => { organizer: { email: "o@example.com#{INJECTION}" } },
        "UID" => { uid: "abc#{INJECTION}" },
        "RRULE" => { rrule: "FREQ=DAILY#{INJECTION}" },
        "URL" => { url: "https://example.com/#{INJECTION}" }
      }

      cases.each do |property, attrs|
        error = assert_raises(ArgumentError, property) { build_event(attrs).generate_calendar_url(:ics) }
        assert_equal "#{property} value must not contain line breaks", error.message
      end
    end

    def test_ical_and_ics_content_share_the_guard
      event = build_event(uid: "abc#{INJECTION}")
      assert_raises(ArgumentError) { event.generate_calendar_url(:ical) }
      assert_raises(ArgumentError) { Providers::IcsContent.new(event).generate }
    end

    def test_url_is_not_text_escaped
      ics = build_event(url: "https://example.com/a,b;c").generate_calendar_url(:ics)
      assert_includes content_lines(ics), "URL:https://example.com/a,b;c"
    end

    # --- Enumerated / numeric values are validated ---

    def test_visibility_must_be_a_known_class
      assert_includes build_event(visibility: "private").generate_calendar_url(:ics), "CLASS:PRIVATE"
      assert_raises(ArgumentError) { build_event(visibility: "public#{INJECTION}").generate_calendar_url(:ics) }
      assert_raises(ArgumentError) { build_event(visibility: "secret").generate_calendar_url(:ics) }
    end

    def test_geo_must_be_numeric
      assert_includes build_event(geo: ["37.5", -122.25]).generate_calendar_url(:ics), "GEO:37.5;-122.25"
      assert_raises(ArgumentError) { build_event(geo: ["1#{INJECTION}", "2"]).generate_calendar_url(:ics) }
      assert_raises(ArgumentError) { build_event(geo: { lat: "north", lng: 2 }).generate_calendar_url(:ics) }
    end

    def test_sequence_must_be_an_integer
      assert_includes build_event(sequence: "3").generate_calendar_url(:ics), "SEQUENCE:3"
      assert_raises(ArgumentError) { build_event(sequence: "1;X").generate_calendar_url(:ics) }
    end
  end
end
