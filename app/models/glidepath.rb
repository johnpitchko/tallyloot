# == Schema Information
#
# Table name: glidepaths
#
#  id          :integer          not null, primary key
#  description :text
#  name        :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_glidepaths_on_name  (name) UNIQUE
#
class Glidepath < ApplicationRecord
  include Inspectable

  has_many :portfolios, dependent: :restrict_with_exception
  has_many :glidepath_steps, dependent: :destroy
  has_many :allocations, through: :glidepath_steps

  validates :name, presence: true, uniqueness: true
  validates :description, presence: true

  before_validation :assign_default_name, on: :create

  inspectable :name, :description

  DEFAULT_GLIDEPATH_NAME = 'Standard Retirement'.freeze

  def self.default
    find_by!(name: DEFAULT_GLIDEPATH_NAME)
  end

  def nominal_return_for_age(age)
    allocation_for_age(age).avg_nominal_return
  end

  def allocation_for_age(age)
    step = glidepath_steps
           .where(start_age: ..age)
           .order(start_age: :desc)
           .first

    raise "No glidepath step found for age #{age} in Glidepath #{id}" unless step

    step.allocation
  end

  private

  def assign_default_name
    self.name ||= DEFAULT_GLIDEPATH_NAME
  end
end
