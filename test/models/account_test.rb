# == Schema Information
#
# Table name: accounts
#
#  id                      :integer          not null, primary key
#  balance                 :integer
#  contribution            :integer          default(0)
#  conversion_age          :integer
#  name                    :string
#  provincial_jurisdiction :string
#  type                    :string           not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  user_id                 :integer          not null
#
# Indexes
#
#  index_accounts_on_type     (type)
#  index_accounts_on_user_id  (user_id)
#
# Foreign Keys
#
#  user_id  (user_id => users.id)
#
require 'test_helper'

class AccountTest < ActiveSupport::TestCase
  def setup
    @tfsa_john = accounts(:tfsa_john)
    @lira_bob = accounts(:lira_bob)
  end

  test 'can withdraw if user is retired' do
    assert @lira_bob.can_withdraw?(2025)
    assert_not @tfsa_john.can_withdraw?(2025)
    assert @tfsa_john.can_withdraw?(2050)
  end
end
