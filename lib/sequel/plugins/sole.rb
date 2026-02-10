# frozen_string_literal: true

module Sequel
  module Plugins
    # The sole plugin adds a +sole+ dataset method that returns the
    # single matching record, raising if zero or more than one record
    # matches.
    #
    #   User.where(login: "alice").sole  # => #<User ...>
    #   User.where(login: "nobody").sole # raises Sequel::NoMatchingRow
    #   User.dataset.sole               # raises Sequel::Plugins::Sole::TooManyRows (if > 1)
    module Sole
      class TooManyRows < Sequel::Error; end

      module DatasetMethods
        def sole
          results = limit(2).all
          raise Sequel::NoMatchingRow.new(self) if results.empty?
          raise TooManyRows, "expected 1 row, got multiple" if results.length > 1

          results.first
        end
      end
    end
  end
end
