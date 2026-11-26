class AddPrimaryTypeToVenues < ActiveRecord::Migration[8.1]
  def change
    add_column :venues, :primary_type, :string
  end
end
