# frozen_string_literal: true

# lib/cal_invite/caching.rb
module CalInvite
  # Cache helpers keyed under CalInvite.configuration.cache_prefix, extended
  # onto CalInvite (CalInvite.fetch_from_cache etc.).
  module Caching
    def fetch_from_cache(key, options = {}, &block)
      full_key = generate_cache_key(key)
      store = CalInvite.configuration.cache_store

      if store.respond_to?(:fetch)
        store.fetch(full_key, options, &block)
      else
        cached = store.read(full_key)
        return cached if cached

        value = block.call
        store.write(full_key, value, options)
        value
      end
    end

    def write_to_cache(key, value, options = {})
      full_key = generate_cache_key(key)
      options[:expires_in] ||= CalInvite.configuration.cache_expires_in
      CalInvite.configuration.cache_store.write(full_key, value, options)
    end

    def read_from_cache(key)
      full_key = generate_cache_key(key)
      CalInvite.configuration.cache_store.read(full_key)
    end

    def clear_cache!
      store = CalInvite.configuration.cache_store
      if store.respond_to?(:delete_matched)
        store.delete_matched("#{CalInvite.configuration.cache_prefix}:*")
      else
        store.clear
      end
    end

    def clear_event_cache!(event_id)
      delete_cache_pattern("events:#{event_id}")
    end

    def clear_provider_cache!(provider)
      delete_cache_pattern("providers:#{provider}")
    end

    def generate_cache_key(*parts)
      ([CalInvite.configuration.cache_prefix] + parts).join(':')
    end

    private

    def delete_cache_pattern(pattern)
      store = CalInvite.configuration.cache_store
      full_pattern = generate_cache_key(pattern)

      if store.respond_to?(:delete_matched)
        store.delete_matched("#{full_pattern}:*")
      else
        # Fallback for stores that don't support pattern deletion
        store.delete(full_pattern)
      end
    end
  end
end
