# frozen_string_literal: true

# app/controllers/meetings_controller.rb
#
# Demonstrates the full send -> reschedule -> cancel lifecycle for an
# RSVP-capable invite: persisting CalInvite::Event#uid/#sequence on a Meeting
# record, then reusing them so mail clients recognize later sends as updates
# to the same event rather than new, unrelated ones.
class MeetingsController < ApplicationController
  def index
    @meetings = Meeting.order(created_at: :desc)
  end

  # Serves the meeting as an .ics file (GET /meetings/:id.ics), cached the
  # way CACHING.md recommends:
  #
  # - stale? sets ETag and Last-Modified from the meeting and answers
  #   304 Not Modified when the client's copy is current, so a calendar app
  #   polling the file gets nothing regenerated. The ETag comes from the
  #   record's version, never from the .ics content: CalInvite writes the
  #   current time into DTSTAMP on every generation, so a content hash would
  #   never match.
  # - Rails.cache keeps the generated content under a key that includes the
  #   meeting's cache_key_with_version (it changes with updated_at, which
  #   reschedules, cancellations, sequence bumps and attendee RSVP changes all
  #   touch) and the iCalendar method. A changed meeting simply misses; nothing
  #   is deleted by hand.
  #
  # Cache-Control stays private (stale?'s default) because the file lists
  # attendee emails, so shared caches and CDNs must not store it.
  def show
    meeting = Meeting.includes(:meeting_attendees).find(params[:id])
    ics_method = meeting.status == "cancelled" ? :cancel : :publish

    respond_to do |format|
      format.ics do
        if stale?(meeting)
          ics = Rails.cache.fetch([meeting, :ics, ics_method]) do
            meeting.to_cal_event.generate_calendar_url(:ics, method: ics_method)
          end
          send_data ics, type: :ics, disposition: "attachment", filename: "#{meeting.title.parameterize}.ics"
        end
      end
    end
  end

  def new
    @meeting = Meeting.new(start_time: 3.days.from_now.change(hour: 10), end_time: 3.days.from_now.change(hour: 11))
  end

  def create
    @meeting = Meeting.new(meeting_params)

    if @meeting.save
      attendee_emails_param.each { |email| @meeting.meeting_attendees.create!(email: email) }
      MeetingMailer.invite(@meeting, method: :request).deliver_later
      redirect_to meetings_path, notice: "Invite sent for \"#{@meeting.title}\"."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # Reschedules the meeting and re-sends it as an updated :request — same
  # uid, incremented sequence, so it replaces the original in attendees'
  # calendars instead of creating a duplicate.
  def reschedule
    meeting = Meeting.find(params[:id])
    meeting.update!(reschedule_params)
    meeting.bump_sequence!

    MeetingMailer.invite(meeting, method: :request).deliver_later
    redirect_to meetings_path, notice: "\"#{meeting.title}\" rescheduled and resent."
  end

  # Sends a real cancellation (METHOD:CANCEL, same uid, incremented sequence)
  # so calendar clients remove the event rather than leaving a stale copy.
  def cancel
    meeting = Meeting.find(params[:id])
    MeetingMailer.invite(meeting, method: :cancel).deliver_later
    meeting.cancel!

    redirect_to meetings_path, notice: "\"#{meeting.title}\" cancelled."
  end

  private

  def meeting_params
    params.require(:meeting).permit(
      :title, :start_time, :end_time, :location, :video_url,
      :description, :timezone, :organizer_name, :organizer_email
    )
  end

  def reschedule_params
    params.require(:meeting).permit(:start_time, :end_time, :location)
  end

  def attendee_emails_param
    params[:meeting][:attendee_emails].to_s.split(",").map(&:strip).reject(&:blank?)
  end
end
