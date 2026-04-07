# frozen_string_literal: true

Sequel.migration do
  change do
    add_column :series, :archived_at, DateTime
  end
end
