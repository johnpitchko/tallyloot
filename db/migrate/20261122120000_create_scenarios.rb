class CreateScenarios < ActiveRecord::Migration[8.0]
  def change
    create_table :scenarios do |t|
      t.references :household, null: false, foreign_key: true
      t.text :raw_input, null: false
      t.json :parsed_levers, default: [], null: false
      t.json :confirmed_levers, default: [], null: false
      t.string :status, default: 'parsed', null: false
      t.text :clarifying_question
      t.datetime :confirmed_at

      t.timestamps
    end

    add_index :scenarios, :status
  end
end
