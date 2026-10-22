# frozen_string_literal: true

# lib/cal_invite/providers/ics_content.rb
module CalInvite
  module Providers
    # ICS content provider, for generating `.ics` content directly (outside
    # Event#generate_calendar_url). Produces the same RFC 5545 content as {Ics};
    # kept for backward compatibility. Pair with {IcsDownload} to serve it as a file.
    #
    # @example
    #   event = CalInvite::Event.new(
    #     title: "Team Meeting",
    #     start_time: Time.now,
    #     end_time: Time.now + 3600
    #   )
    #   ics_content = CalInvite::Providers::IcsContent.new(event).generate
    #
    # @see Ics
    class IcsContent < Ics
    end

    # Module for handling ICS file downloads with proper headers and file naming.
    # Provides utility methods for preparing ICS content for HTTP download.
    module IcsDownload
      # Generates appropriate HTTP headers for ICS file download.
      #
      # @param filename [String] The desired filename for the download
      # @param method [Symbol, nil] The iCalendar METHOD used to generate the content
      #   (:publish or :request). When given, it's added as a `method` parameter on
      #   the Content-Type header — this is what lets mail clients (Gmail, Outlook,
      #   Apple Mail) recognize the attachment as a meeting invite and render RSVP
      #   actions instead of a plain file attachment. Must match the METHOD in the
      #   .ics content itself.
      # @return [Hash] HTTP headers for the ICS file download
      def self.headers(filename, method: nil)
        content_type = 'text/calendar; charset=UTF-8'
        content_type += "; method=#{method == :decline_counter ? 'DECLINECOUNTER' : method.to_s.upcase}" if method

        {
          'Content-Type' => content_type,
          'Content-Disposition' => "attachment; filename=#{sanitize_filename(filename)}"
        }
      end

      # Sanitizes a filename by removing potentially problematic characters.
      #
      # @param filename [String] The filename to sanitize
      # @return [String] The sanitized filename
      def self.sanitize_filename(filename)
        filename.gsub(/[^0-9A-Za-z.\-]/, '_')
      end

      # Wraps ICS content with appropriate download information.
      #
      # @param content [String] The ICS calendar content
      # @param title [String] The event title to use in the filename
      # @param method [Symbol, nil] The iCalendar METHOD used to generate `content`
      #   (:publish or :request); forwarded to {headers}. Must match the METHOD
      #   used when generating `content` itself.
      # @return [Hash] Hash containing content and headers for download
      # @example
      #   result = IcsDownload.wrap_for_download(ics_content, "team-meeting")
      #   # => { content: "BEGIN:VCALENDAR...", headers: { 'Content-Type' => '...' } }
      def self.wrap_for_download(content, title, method: nil)
        filename = sanitize_filename("#{title.downcase}_#{Time.now.strftime('%Y%m%d')}.ics")
        {
          content: content,
          headers: headers(filename, method: method)
        }
      end
    end
  end
end
