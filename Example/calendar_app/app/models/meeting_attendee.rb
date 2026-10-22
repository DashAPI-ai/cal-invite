# frozen_string_literal: true

# Mirrors CalInvite's attendee partstat values, kept in sync by whatever
# reply channel the host app wires up (see EventRepliesController for an
# illustrative inbound-email example).
class MeetingAttendee < ApplicationRecord
  PARTSTATS = %w[needs_action accepted declined tentative delegated].freeze

  # Touching the meeting when an attendee is added or their RSVP changes
  # expires the meeting's cached .ics download (MeetingsController#show).
  belongs_to :meeting, touch: true

  validates :email, presence: true, uniqueness: { scope: :meeting_id }
  validates :partstat, inclusion: { in: PARTSTATS }
end
