# frozen_string_literal: true

require "sqlite3"

module DailyPlaylistCoverCreator
  class ImageUrlDatabase
    def initialize(path)
      @path = path
    end

    def each_random_image_name
      return enum_for(:each_random_image_name) unless block_given?

      database = SQLite3::Database.new(@path, readonly: true)
      total = database.get_first_value("SELECT COUNT(*) FROM image_urls").to_i
      tried_offsets = {}

      while tried_offsets.length < total
        offset = rand(total)
        next if tried_offsets.key?(offset)

        tried_offsets[offset] = true
        image_name = image_name_at_offset(database, offset)
        yield image_name if image_name
      end
    ensure
      database&.close
    end

    private

    def image_name_at_offset(database, offset)
      statement = database.prepare("SELECT image_name FROM image_urls LIMIT 1 OFFSET ?")
      cursor = statement.execute(offset)
      cursor.next&.first
    ensure
      cursor&.close
    end
  end
end
