# test/cal_invite/load_test.rb
require 'test_helper'
require 'open3'
require 'rbconfig'

module CalInvite
  class LoadTest < Minitest::Test
    # Runs in a fresh process: this test process may have loaded extra
    # ActiveSupport extensions through other libraries. Compares against a
    # bare `require "active_support"`, which itself patches some core classes
    # on older ActiveSupport versions (e.g. Object#blank? on 7.0).
    def test_requiring_the_gem_does_not_load_all_core_extensions
      script = <<~RUBY
        probe = -> { [1.respond_to?(:hours), nil.respond_to?(:blank?), "".respond_to?(:squish)] }
        require "logger"
        require "active_support"
        baseline = probe.call
        require "cal_invite"
        abort("cal_invite patched core classes: \#{baseline} -> \#{probe.call}") unless probe.call == baseline
      RUBY
      lib = File.expand_path('../../lib', __dir__)
      _out, err, status = Open3.capture3(RbConfig.ruby, '-I', lib, '-e', script)

      assert status.success?, err
    end
  end
end
