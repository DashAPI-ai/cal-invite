# frozen_string_literal: true

# lib/cal_invite/providers/ical.rb
module CalInvite
  module Providers
    # iCalendar provider (`:ical`), for Apple Calendar and other iCalendar apps.
    # Produces the same RFC 5545 content as {Ics}; kept as its own provider
    # symbol for backward compatibility.
    #
    # @example
    #   event = CalInvite::Event.new(
    #     title: "Team Meeting",
    #     start_time: Time.now,
    #     end_time: Time.now + 3600,
    #     timezone: 'America/New_York'
    #   )
    #   ics_content = CalInvite::Providers::Ical.new(event).generate
    #
    # @see Ics
    class Ical < Ics
    end
  end
end
