class AddMealPeriodToNomikais < ActiveRecord::Migration[8.1]
  def change
    add_column :nomikais, :meal_period, :string, default: "dinner", null: false
  end
end
