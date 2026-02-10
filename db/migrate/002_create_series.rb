# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:series) do
      primary_key :id
      foreign_key :user_id, :users, null: false
      String :note, null: false
      String :interval_unit, null: false
      Integer :interval_count, null: false, default: 1

      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      constraint(:valid_interval_unit) { Sequel.lit("interval_unit IN ('day', 'week', 'month', 'quarter', 'year')") }
      constraint(:positive_interval_count) { Sequel.lit("interval_count >= 1") }
    end
  end
end
