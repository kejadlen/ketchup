Sequel.migration do
  change do
    alter_table(:series) do
      add_column :shared, TrueClass, default: false, null: false
    end
    alter_table(:tasks) do
      add_foreign_key :completed_by_user_id, :users, null: true
    end
    from(:tasks).exclude(completed_at: nil).update(
      completed_by_user_id: from(:series).where(id: Sequel[:tasks][:series_id]).select(:user_id)
    )
    alter_table(:tasks) do
      add_constraint(:tasks_completed_by_consistency) do
        Sequel.lit("(completed_at IS NULL AND completed_by_user_id IS NULL) OR (completed_at IS NOT NULL AND completed_by_user_id IS NOT NULL)")
      end
      add_index [:series_id], unique: true, where: Sequel.lit("completed_at IS NULL"), name: :one_active_task_per_series
    end
  end
end
