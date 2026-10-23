# frozen_string_literal: true

# app/controllers/event_replies_controller.rb
#
# ILLUSTRATIVE, NOT PRODUCTION-READY. CalInvite only generates outbound
# invites — when an attendee clicks Accept/Decline in their mail client,
# their calendar app emails an iTIP `METHOD:REPLY` back to the organizer's
# *mailbox*, not to this app. To turn that into a webhook, point an inbound
# email provider (SendGrid Inbound Parse, Postmark Inbound, AWS SES + SNS,
# Mailgun Routes, ...) at the organizer address and have it POST the raw
# MIME message here.
#
# This controller shows the shape of that handler using a plain regex
# extraction of the `text/calendar` part. For production, parse with a real
# iCalendar parser (e.g. the `icalendar` gem) instead of regexes — mail
# clients vary in how they fold/escape lines, and a regex will eventually
# choke on something a real parser wouldn't.
#
# See CONFIGURATION.md's "Tracking RSVPs" for the full picture, including
# why raw .ics email invites often can't be tracked this way at all unless
# the organizer address is backed by a real mailbox/calendar system.
class EventRepliesController < ApplicationController
  def create
    mail = Mail.read_from_string(inbound_raw_mime)
    calendar_part = mail.all_parts.find { |part| part.content_type.to_s.include?("text/calendar") } || mail

    body = calendar_part.body.decoded
    return head :unprocessable_entity unless body.include?("METHOD:REPLY")

    uid = body[/UID:(\S+)/, 1]
    meeting = uid && Meeting.find_by(uid: uid)
    return head :not_found unless meeting

    body.scan(/ATTENDEE[^\r\n:]*PARTSTAT=([A-Z-]+)[^\r\n:]*:mailto:([^\r\n]+)/i) do |partstat, email|
      attendee = meeting.meeting_attendees.find_or_initialize_by(email: email.strip.downcase)
      attendee.update!(partstat: partstat.downcase.tr("-", "_"))
    end

    head :ok
  end

  private

  # Adjust to match your inbound email provider's payload shape — e.g.
  # SendGrid Inbound Parse posts the raw MIME as params[:email];
  # Postmark posts parsed JSON (no raw MIME) and would need different
  # handling entirely.
  def inbound_raw_mime
    params[:email] || request.raw_post
  end
end
