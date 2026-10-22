# test/cal_invite/configuration_test.rb
require 'test_helper'

module CalInvite
  class ConfigurationTest < Minitest::Test
    def test_cache_settings_are_deprecated_but_still_accepted
      config = Configuration.new

      _, stderr = capture_io do
        config.cache_store = :memory_store
        config.cache_prefix = 'my_app'
        config.cache_expires_in = 3600
      end

      %w[cache_store cache_prefix cache_expires_in].each do |name|
        assert_match(/Configuration##{name}= is deprecated and has no effect/, stderr)
      end
      # Still stored, so app code reading them (e.g. cache_store.clear in test setup) keeps working.
      assert_kind_of ActiveSupport::Cache::MemoryStore, config.cache_store
      assert_equal 'my_app', config.cache_prefix
      assert_equal 3600, config.cache_expires_in
    end

    def test_cache_helpers_are_gone
      refute CalInvite.respond_to?(:fetch_from_cache)
      refute defined?(CalInvite::Caching)
    end
  end
end
