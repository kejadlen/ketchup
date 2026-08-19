Sequel.migration do
  change do
    alter_table(:users) do
      add_column :email, String
      drop_column :name
    end
  end
end
