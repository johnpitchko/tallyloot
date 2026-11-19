# Squashed from the project's earlier migrations when it was open-sourced. The
# version matches the last of those, so existing databases treat it as applied.
# It reproduces the existing schema exactly, nullable booleans included.
# rubocop:disable Rails/ThreeStateBooleanColumn
class CreateSchema < ActiveRecord::Migration[8.0]
  def change
    create_table 'accounts' do |t|
      t.string 'name'
      t.integer 'balance'
      t.integer 'user_id', null: false
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.integer 'contribution', default: 0
      t.integer 'conversion_age'
      t.string 'type', null: false
      t.string 'provincial_jurisdiction'
      t.index ['type'], name: 'index_accounts_on_type'
      t.index ['user_id'], name: 'index_accounts_on_user_id'
    end

    create_table 'allocations' do |t|
      t.decimal 'equity_pct', precision: 5, scale: 4, null: false
      t.decimal 'fixed_income_pct', precision: 5, scale: 4, null: false
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.string 'name'
      t.text 'description'
      t.decimal 'avg_nominal_return', precision: 5, scale: 4, default: '0.0', null: false
      t.decimal 'std_dev', precision: 5, scale: 4, default: '0.0', null: false
    end

    create_table 'benefits' do |t|
      t.integer 'user_id', null: false
      t.string 'name'
      t.integer 'annual_amount'
      t.integer 'start_age'
      t.boolean 'inflation_indexed'
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.string 'type', default: 'Benefit::Custom', null: false
      t.index ['type'], name: 'index_benefits_on_type'
      t.index ['user_id'], name: 'index_benefits_on_user_id'
    end

    create_table 'employments' do |t|
      t.integer 'user_id', null: false
      t.string 'label'
      t.integer 'annual_income', default: 0, null: false
      t.integer 'start_age', null: false
      t.integer 'end_age', null: false
      t.string 'currency_code', default: 'CAD', null: false
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.index ['user_id'], name: 'index_employments_on_user_id', unique: true
    end

    create_table 'glidepath_steps' do |t|
      t.integer 'glidepath_id', null: false
      t.integer 'start_age', null: false
      t.integer 'allocation_id', null: false
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.index ['allocation_id'], name: 'index_glidepath_steps_on_allocation_id'
      t.index ['glidepath_id'], name: 'index_glidepath_steps_on_glidepath_id'
    end

    create_table 'glidepaths' do |t|
      t.string 'name', null: false
      t.text 'description'
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.index ['name'], name: 'index_glidepaths_on_name', unique: true
    end

    create_table 'households' do |t|
      t.integer 'retirement_income_goal'
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.string 'province'
      t.boolean 'sample_data', default: false, null: false
    end

    create_table 'pensions' do |t|
      t.string 'name'
      t.boolean 'inflation_indexed'
      t.integer 'user_id', null: false
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.decimal 'annual_amount', precision: 10, scale: 2, default: '0.0', null: false
      t.string 'description'
      t.integer 'start_age', null: false
      t.integer 'normal_retirement_age', default: 65
      t.decimal 'early_reduction_rate', precision: 5, scale: 4
      t.decimal 'late_increase_rate', precision: 5, scale: 4
      t.index ['user_id'], name: 'index_pensions_on_user_id'
    end

    create_table 'portfolios' do |t|
      t.integer 'glidepath_id', null: false
      t.integer 'household_id', null: false
      t.decimal 'inflation_rate', precision: 5, scale: 2
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.boolean 'spending_smile_enabled', default: false, null: false
      t.index ['glidepath_id'], name: 'index_portfolios_on_glidepath_id'
      t.index ['household_id'], name: 'index_portfolios_on_household_id'
    end

    create_table 'users' do |t|
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.date 'birth_date', null: false
      t.integer 'household_id'
      t.string 'name'
      t.integer 'life_expectancy', default: 82, null: false
      t.integer 'retirement_age', default: 65, null: false
      t.index ['household_id'], name: 'index_users_on_household_id'
    end

    add_foreign_key 'accounts', 'users'
    add_foreign_key 'benefits', 'users'
    add_foreign_key 'employments', 'users'
    add_foreign_key 'glidepath_steps', 'allocations'
    add_foreign_key 'glidepath_steps', 'glidepaths'
    add_foreign_key 'pensions', 'users'
    add_foreign_key 'portfolios', 'glidepaths'
    add_foreign_key 'portfolios', 'households'
    add_foreign_key 'users', 'households'
  end
end
# rubocop:enable Rails/ThreeStateBooleanColumn
