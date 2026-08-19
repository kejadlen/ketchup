Sequel.migration do
  change do
    alter_table(:tasks) do
      add_column :note, String
    end
  end
end
