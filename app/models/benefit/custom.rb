# == Schema Information
#
# Table name: benefits
#
#  id                :integer          not null, primary key
#  annual_amount     :integer
#  inflation_indexed :boolean
#  name              :string
#  start_age         :integer
#  type              :string           default("Benefit::Custom"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  user_id           :integer          not null
#
# Indexes
#
#  index_benefits_on_type     (type)
#  index_benefits_on_user_id  (user_id)
#
# Foreign Keys
#
#  user_id  (user_id => users.id)
#
class Benefit
  class Custom < Benefit
    def type_name = 'Other Benefit'
    def government_benefit? = false
    def inflation_indexed? = inflation_indexed

    # Custom benefits use the base class implementation
    # with user-configurable inflation indexing
  end
end
