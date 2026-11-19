ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

# The app acts as the single household's first member, but fixtures hold
# several households. Integration tests pick which fixture user requests act as.
module TestOwner
  mattr_accessor :user

  def owner
    TestOwner.user || super
  end

  # Mixed into integration and system tests.
  module Helpers
    extend ActiveSupport::Concern

    included do
      teardown { TestOwner.user = nil }
    end

    def act_as(user)
      TestOwner.user = user
    end
  end
end
SelfHosted.singleton_class.prepend(TestOwner)
ActionDispatch::IntegrationTest.include(TestOwner::Helpers)
