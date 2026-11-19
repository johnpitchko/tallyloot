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
class Account
  class NonRegistered < Account
    def type_name = 'Non-Registered'
    def taxable? = true

    # Non-registered withdraws first (after mandatory minimums)
    def withdrawal_priority = 1
  end
end
