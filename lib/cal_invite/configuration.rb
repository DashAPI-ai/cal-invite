# frozen_string_literal: true

# lib/cal_invite/configuration.rb
# Configuration class for the CalInvite gem.
# Handles all configurable options including cache settings, timezone, and webhook secrets.
#
# @attr_reader [ActiveSupport::Cache::Store, nil] cache_store The cache store to use
# @attr_reader [String] cache_prefix The prefix to use for cache keys
# @attr_reader [Integer] cache_expires_in The default cache expiration time in seconds
# @attr_reader [String, nil] webhook_secret The secret key for webhook verification
# @attr_reader [String] timezone The default timezone for events
module CalInvite
  class Configuration
    attr_reader :cache_store, :cache_prefix, :cache_expires_in, :webhook_secret, :timezone

    # Initializes a new Configuration instance with default values.
    def initialize
      @cache_store = nil
      @cache_prefix = 'cal_invite'
      @cache_expires_in = 24.hours # now this will work with active_support loaded
      @webhook_secret = nil
      @timezone = 'UTC'
    end

    # Sets the cache store backing the CalInvite cache helpers (CalInvite.fetch_from_cache etc.).
    # Event#generate_calendar_url never caches its output.
    #
    # @param store [Symbol, #read, #write, #delete] The cache store to use
    # @raise [ArgumentError] If an unsupported cache store is provided
    #
    # @example Set memory store
    #   config.cache_store = :memory_store
    def cache_store=(store)
      @cache_store = case store
      when :memory_store
        ActiveSupport::Cache::MemoryStore.new
      when :null_store
        ActiveSupport::Cache::NullStore.new
      when Symbol
        raise ArgumentError, "Unsupported cache store: #{store}"
      else
        # Allow custom cache store objects that respond to read/write/delete
        unless store.respond_to?(:read) && store.respond_to?(:write) && store.respond_to?(:delete)
          raise ArgumentError, "Custom cache store must implement read/write/delete methods"
        end
        store
      end
    end

    # Sets the prefix used for cache keys.
    #
    # @param prefix [#to_s] The prefix to use for cache keys
    def cache_prefix=(prefix)
      @cache_prefix = prefix.to_s
    end

    # Sets the default cache expiration time.
    #
    # @param duration [#to_i] The duration in seconds
    def cache_expires_in=(duration)
      @cache_expires_in = duration.to_i
    end

    # Sets the webhook secret for verification.
    #
    # @param secret [String, nil] The secret key
    def webhook_secret=(secret)
      @webhook_secret = secret
    end

    # Sets the default timezone for events.
    #
    # @param tz [#to_s] The timezone identifier
    def timezone=(tz)
      @timezone = tz.to_s
    end
  end
end
