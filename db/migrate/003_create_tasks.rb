# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:tasks) do
      primary_key :id
      foreign_key :series_id, :series, null: false
      Date :due_date, null: false
      DateTime :completed_at
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      index [:series_id], unique: true, where: Sequel.lit("completed_at IS NULL"), name: :one_active_task_per_series
    end
  end
end
