# test/cal_invite/caching_test.rb
require 'test_helper'

module CalInvite
  class CachingTest < Minitest::Test
    def setup
      super
      @original_store = CalInvite.configuration.cache_store
      @original_prefix = CalInvite.configuration.cache_prefix
      CalInvite.configuration.cache_store = :memory_store
      CalInvite.configuration.cache_prefix = 'test_prefix'
    end

    def teardown
      CalInvite.configuration.cache_store = @original_store
      CalInvite.configuration.cache_prefix = @original_prefix
    end

    def store
      CalInvite.configuration.cache_store
    end

    def test_read_and_write_use_the_prefix
      CalInvite.write_to_cache('events:42:ics', 'content')

      assert_equal 'content', CalInvite.read_from_cache('events:42:ics')
      assert_equal 'content', store.read('test_prefix:events:42:ics')
    end

    def test_fetch_from_cache_computes_once
      calls = 0
      2.times { assert_equal 'v', CalInvite.fetch_from_cache('k') { calls += 1; 'v' } }

      assert_equal 1, calls
    end

    def test_clear_helpers
      CalInvite.write_to_cache('events:1:ics', 'a')
      CalInvite.write_to_cache('events:2:ics', 'b')
      CalInvite.write_to_cache('providers:ics:x', 'c')
      store.write('other_app:key', 'keep')

      CalInvite.clear_event_cache!(1)
      assert_nil CalInvite.read_from_cache('events:1:ics')
      assert_equal 'b', CalInvite.read_from_cache('events:2:ics')

      CalInvite.clear_provider_cache!(:ics)
      assert_nil CalInvite.read_from_cache('providers:ics:x')

      CalInvite.clear_cache!
      assert_nil CalInvite.read_from_cache('events:2:ics')
      assert_equal 'keep', store.read('other_app:key')
    end
  end
end
