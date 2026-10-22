require "test_helper"

class MeetingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    # The test environment uses :null_store; these tests need a real cache.
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    @meeting = Meeting.create!(
      title: "Design review",
      start_time: Time.utc(2026, 11, 2, 15), end_time: Time.utc(2026, 11, 2, 16),
      timezone: "America/New_York",
      organizer_name: "Jane Doe", organizer_email: "jane@example.com"
    )
    @attendee = @meeting.meeting_attendees.create!(email: "guest@example.com")
  end

  teardown do
    Rails.cache = @original_cache
  end

  test "the meetings page links to each meeting's .ics download" do
    get meetings_url

    assert_response :success
    assert_select "a[href=?]", meeting_path(@meeting, format: :ics), text: "Download .ics"
  end

  test "serves the meeting as an .ics file" do
    get meeting_url(@meeting, format: :ics)

    assert_response :success
    assert_equal "text/calendar", response.media_type
    assert_includes response.body, "UID:#{@meeting.uid}"
    assert_includes response.body, "METHOD:PUBLISH"
    assert_includes response.headers["Cache-Control"], "private"
    assert response.headers["ETag"].present?
  end

  test "answers 304 when the client's copy is current" do
    get meeting_url(@meeting, format: :ics)
    get meeting_url(@meeting, format: :ics), headers: { "If-None-Match" => response.headers["ETag"] }

    assert_response :not_modified
    assert_empty response.body
  end

  test "reuses the cached .ics until the meeting changes" do
    get meeting_url(@meeting, format: :ics)
    first = response.body

    # A fresh generation would carry a new DTSTAMP; the cached copy keeps it.
    travel 1.minute do
      get meeting_url(@meeting, format: :ics)
    end

    assert_equal first, response.body
  end

  test "an attendee's RSVP change expires the ETag and the cached .ics" do
    get meeting_url(@meeting, format: :ics)
    etag = response.headers["ETag"]

    travel 1.second do
      @attendee.update!(partstat: "accepted")
      get meeting_url(@meeting, format: :ics), headers: { "If-None-Match" => etag }
    end

    assert_response :success
    assert_includes response.body, "PARTSTAT=ACCEPTED"
  end

  test "a cancelled meeting is served as a cancellation with a higher sequence" do
    get meeting_url(@meeting, format: :ics)
    etag = response.headers["ETag"]

    travel 1.second do
      @meeting.cancel!
      get meeting_url(@meeting, format: :ics), headers: { "If-None-Match" => etag }
    end

    assert_response :success
    assert_includes response.body, "METHOD:CANCEL"
    assert_includes response.body, "SEQUENCE:1"
  end
end
