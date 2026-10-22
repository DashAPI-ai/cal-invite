# frozen_string_literal: true

# Demonstrates the persistence pattern CalInvite expects host apps to own:
# a stable `uid` (generated once, reused on every subsequent send) and a
# `sequence` counter (bumped on every reschedule/cancel). See
# CONFIGURATION.md's "Updating and cancelling invites" for the underlying
# iCalendar rules this maps to.
class Meeting < ApplicationRecord
  has_many :meeting_attendees, dependent: :destroy

  validates :title, :start_time, :end_time, :organizer_name, :organizer_email, presence: true

  before_validation :assign_uid, on: :create

  # Builds the CalInvite::Event for this meeting's *current* state, reusing
  # the persisted uid/sequence so mail clients tie it back to prior sends.
  def to_cal_event
    CalInvite::Event.new(
      title: title,
      start_time: start_time.utc,
      end_time: end_time.utc,
      location: location,
      url: video_url,
      description: description,
      timezone: timezone,
      organizer: { name: organizer_name, email: organizer_email },
      attendees: meeting_attendees.map { |a| { email: a.email, name: a.name, partstat: a.partstat.to_sym } },
      show_attendees: true,
      uid: uid,
      sequence: sequence
    )
  end

  # Call before resending a :request for a changed meeting, or before a :cancel.
  # RFC 5545 requires SEQUENCE to strictly increase for clients to treat the
  # new message as superseding the last one.
  def bump_sequence!
    # touch: true also bumps updated_at, which the cached .ics download is keyed
    # on (MeetingsController#show); increment! alone leaves it unchanged.
    increment!(:sequence, touch: true)
  end

  def cancel!
    bump_sequence!
    update!(status: "cancelled")
  end

  private

  def assign_uid
    self.uid ||= "#{SecureRandom.uuid}@cal-invite-example"
  end
end
