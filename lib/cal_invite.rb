# lib/cal_invite.rb
require 'logger'
require 'mutex_m'
require 'bigdecimal'
require 'active_support'
require 'securerandom'
require 'time'
require 'uri'

require 'cal_invite/version'
require 'cal_invite/configuration'
require 'cal_invite/ical_timezone'
require 'cal_invite/event'
require 'cal_invite/providers'

# The main module for the CalInvite gem. This module provides functionality for generating
# calendar invites across different calendar providers.
#
# @example Configure the gem
#   CalInvite.configure do |config|
#     config.timezone = 'America/New_York'
#   end
#
# @example Create and generate a calendar URL
#   event = CalInvite::Event.new(
#     title: "Team Meeting",
#     start_time: Time.now,
#     end_time: Time.now + 3600
#   )
#   google_url = event.generate_calendar_url(:google)
#
module CalInvite
  class Error < StandardError; end

  class << self
    # Returns the current configuration object.
    # @return [CalInvite::Configuration] The current configuration object
    attr_accessor :configuration

    # Configures the CalInvite gem through a block.
    #
    # @yield [config] The configuration object to be modified
    # @yieldparam config [CalInvite::Configuration] The configuration object
    # @return [void]
    #
    # @example
    #   CalInvite.configure do |config|
    #     config.timezone = 'UTC'
        #   end
    def configure
      self.configuration ||= Configuration.new
      yield(configuration)
    end

    # Resets the configuration to default values.
    #
    # @return [void]
    def reset_configuration!
      self.configuration = Configuration.new
    end
  end
end
