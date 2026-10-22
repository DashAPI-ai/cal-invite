# frozen_string_literal: true

# lib/cal_invite/configuration.rb
# Configuration class for the CalInvite gem.
# Handles all configurable options: timezone and webhook secret.
#
# @attr_reader [ActiveSupport::Cache::Store, nil] cache_store Deprecated, unused; removed in 0.4.0
# @attr_reader [String] cache_prefix Deprecated, unused; removed in 0.4.0
# @attr_reader [Integer] cache_expires_in Deprecated, unused; removed in 0.4.0
# @attr_reader [String, nil] webhook_secret The secret key for webhook verification
# @attr_reader [String] timezone The default timezone for events
module CalInvite
  class Configuration
    attr_reader :cache_store, :cache_prefix, :cache_expires_in, :webhook_secret, :timezone

    # Initializes a new Configuration instance with default values.
    def initialize
      @cache_store = nil
      @cache_prefix = 'cal_invite'
      @cache_expires_in = 24 * 60 * 60
      @webhook_secret = nil
      @timezone = 'UTC'
    end

    # @deprecated CalInvite caches nothing, so this setting has no effect.
    #   It warns, and will be removed in 0.4.0.
    #
    # @param store [Symbol, #read, #write, #delete] The cache store to use
    # @raise [ArgumentError] If an unsupported cache store is provided
    def cache_store=(store)
      warn_deprecated_cache_setting(:cache_store)
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

    # @deprecated Has no effect; warns, and will be removed in 0.4.0.
    #
    # @param prefix [#to_s] The prefix to use for cache keys
    def cache_prefix=(prefix)
      warn_deprecated_cache_setting(:cache_prefix)
      @cache_prefix = prefix.to_s
    end

    # @deprecated Has no effect; warns, and will be removed in 0.4.0.
    #
    # @param duration [#to_i] The duration in seconds
    def cache_expires_in=(duration)
      warn_deprecated_cache_setting(:cache_expires_in)
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

    private

    def warn_deprecated_cache_setting(name)
      warn "[cal_invite] Configuration##{name}= is deprecated and has no effect: " \
           "CalInvite no longer caches anything. Remove it; it will be removed in 0.4.0.",
           uplevel: 2
    end
  end
end
