# == Schema Information
#
# Table name: users
#
#  id              :integer          not null, primary key
#  birth_date      :date             not null
#  life_expectancy :integer          default(82), not null
#  name            :string
#  retirement_age  :integer          default(65), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  household_id    :integer
#
# Indexes
#
#  index_users_on_household_id  (household_id)
#
# Foreign Keys
#
#  household_id  (household_id => households.id)
#
require 'test_helper'

# rubocop:disable Metrics/ClassLength
class UserTest < ActiveSupport::TestCase
  def setup
    @john = users(:working_user_john)
    @jane = users(:working_user_jane)
  end

  test 'calculate user age' do
    assert_equal 46, @john.age_in_year
    assert_equal 50, @john.age_in_year(2030)
  end

  test 'age does not count birthday until it has passed this year' do
    travel_to Date.new(2026, 4, 24) do
      user = User.new(birth_date: Date.new(1985, 9, 15))
      assert_equal 40, user.age
    end
  end

  test 'age increments on the birthday' do
    travel_to Date.new(2026, 9, 15) do
      user = User.new(birth_date: Date.new(1985, 9, 15))
      assert_equal 41, user.age
    end
  end

  test 'age counts correctly when birthday has already passed this year' do
    travel_to Date.new(2026, 4, 24) do
      user = User.new(birth_date: Date.new(1980, 1, 1))
      assert_equal 46, user.age
    end
  end

  test 'calculate life expectancy year' do
    assert_equal 2062, @john.life_expectancy_year # 1980 + 82
    assert_equal 2063, @jane.life_expectancy_year # 1981 + 82
  end

  test 'calculate retirement year' do
    assert_equal 2045, @john.retirement_year # 1980 + 65
    assert_equal 2046, @jane.retirement_year # 1981 + 65
  end

  test 'determine if user is retired in a given year' do
    assert_not @john.retired_as_of?(2040)
    assert @john.retired_as_of?(2045)
    assert @john.retired_as_of?(2050)

    assert_not @jane.retired_as_of?(2040)
    assert @jane.retired_as_of?(2046) # 1981 + 65
    assert @jane.retired_as_of?(2050)
  end

  # Name validation tests
  test 'allows valid names with letters, spaces, hyphens, apostrophes' do
    valid_names = ['John', 'Mary-Jane', "O'Brien", 'José', 'François', 'Van der Berg', 'Müller']

    valid_names.each do |name|
      @john.name = name
      assert @john.valid?, "Expected '#{name}' to be valid, but got: #{@john.errors[:name]}"
    end
  end

  test 'rejects names with special characters' do
    invalid_names = ['John&^&', 'Test123', 'Name!', 'Hello@World', 'Test#Name']

    invalid_names.each do |name|
      @john.name = name
      assert_not @john.valid?, "Expected '#{name}' to be invalid"
      assert_includes @john.errors[:name], 'can only contain letters, spaces, hyphens, and apostrophes'
    end
  end

  test 'allows blank names' do
    @john.name = ''
    assert @john.valid?
  end

  # Birth date validation tests
  test 'rejects birth date in the future' do
    @john.birth_date = 1.day.from_now.to_date
    assert_not @john.valid?
    assert_includes @john.errors[:birth_date], 'cannot be in the future'
  end

  test 'rejects birth date more than 120 years ago' do
    @john.birth_date = 121.years.ago.to_date
    assert_not @john.valid?
    assert_includes @john.errors[:birth_date], 'is too far in the past'
  end

  test 'rejects birth date for users under 18' do
    @john.birth_date = 17.years.ago.to_date
    assert_not @john.valid?
    assert_includes @john.errors[:birth_date], 'must be at least 18 years old'
  end

  test 'allows valid birth dates' do
    @john.birth_date = 30.years.ago.to_date
    assert @john.valid?

    @john.birth_date = 18.years.ago.to_date
    assert @john.valid?

    @john.birth_date = 100.years.ago.to_date
    assert @john.valid?
  end
end
# rubocop:enable Metrics/ClassLength
