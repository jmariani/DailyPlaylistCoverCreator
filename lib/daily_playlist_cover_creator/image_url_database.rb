# frozen_string_literal: true

require "sqlite3"

module DailyPlaylistCoverCreator
  class ImageUrlDatabase
    MAX_RANDOM_ATTEMPTS = 2_000

    def initialize(path)
      @path = path
    end

    def each_random_image_name
      return enum_for(:each_random_image_name) unless block_given?

      database = SQLite3::Database.new(@path, readonly: true)
      max_rowid = database.get_first_value("SELECT MAX(rowid) FROM image_urls").to_i
      return if max_rowid.zero?

      yielded_rowids = {}
      attempts = 0

      while attempts < MAX_RANDOM_ATTEMPTS
        attempts += 1
        row = image_row_at_or_after_random_rowid(database, max_rowid)
        next unless row
        next if yielded_rowids.key?(row.fetch(:rowid))

        yielded_rowids[row.fetch(:rowid)] = true
        yield row.fetch(:image_name)
      end
    ensure
      database&.close
    end

    def delete_image_name(image_name)
      database = SQLite3::Database.new(@path)
      database.execute("DELETE FROM image_urls WHERE image_name = ?", [image_name])
    ensure
      database&.close
    end

    private

    def image_row_at_or_after_random_rowid(database, max_rowid)
      target_rowid = rand(1..max_rowid)
      row = image_row_at_or_after_rowid(database, target_rowid)
      row || first_image_row(database)
    end

    def image_row_at_or_after_rowid(database, rowid)
      fetch_image_row(database, "SELECT rowid, image_name FROM image_urls WHERE rowid >= ? ORDER BY rowid LIMIT 1", rowid)
    end

    def first_image_row(database)
      fetch_image_row(database, "SELECT rowid, image_name FROM image_urls ORDER BY rowid LIMIT 1")
    end

    def fetch_image_row(database, sql, *binds)
      statement = database.prepare(sql)
      cursor = statement.execute(*binds)
      row = cursor.next
      return nil unless row

      { rowid: row[0], image_name: row[1] }
    ensure
      cursor&.close
    end
  end
end
