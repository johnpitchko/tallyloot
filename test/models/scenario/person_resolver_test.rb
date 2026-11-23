require 'test_helper'

class Scenario::PersonResolverTest < ActiveSupport::TestCase
  setup do
    @household = households(:non_retired)
    @john = users(:working_user_john)
    @jane = users(:working_user_jane)
    @resolver = Scenario::PersonResolver.new(@household, @john)
  end

  test 'resolves self to the current user' do
    assert_equal @john, @resolver.resolve('self')
  end

  test 'resolves spouse to the other household member' do
    assert_equal @jane, @resolver.resolve('spouse')
  end

  test 'resolves a name case-insensitively' do
    assert_equal @jane, @resolver.resolve('jane')
    assert_equal @jane, @resolver.resolve('JANE')
    assert_equal @john, @resolver.resolve('John')
  end

  test 'raises when spouse is requested in a single-member household' do
    solo = users(:single_user)
    resolver = Scenario::PersonResolver.new(households(:single), solo)

    error = assert_raises(Scenario::PersonResolver::AmbiguousPersonError) do
      resolver.resolve('spouse')
    end
    assert_match(/no spouse/i, error.message)
  end

  test 'raises on an unknown name' do
    error = assert_raises(Scenario::PersonResolver::AmbiguousPersonError) do
      @resolver.resolve('Gandalf')
    end
    assert_match(/Gandalf/, error.message)
  end

  test 'raises on a blank reference' do
    assert_raises(Scenario::PersonResolver::AmbiguousPersonError) { @resolver.resolve(nil) }
    assert_raises(Scenario::PersonResolver::AmbiguousPersonError) { @resolver.resolve('') }
  end
end
