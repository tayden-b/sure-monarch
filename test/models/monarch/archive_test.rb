require "test_helper"

class Monarch::ArchiveTest < ActiveSupport::TestCase
  # Builds a minimal archive directory holding the given collections and an
  # optional VALIDATION.json at the root.
  def build_archive(collections = {}, validation = nil)
    dir = Dir.mktmpdir
    import_dir = Pathname.new(dir).join("import")
    FileUtils.mkdir_p(import_dir)
    collections.each do |name, records|
      import_dir.join("#{name}.json").write(JSON.pretty_generate(records))
    end
    Pathname.new(dir).join("VALIDATION.json").write(JSON.pretty_generate(validation)) if validation
    Monarch::Archive.new(dir)
  end

  test "as_of_date comes from VALIDATION.json's generated_at" do
    archive = build_archive(
      { "balance_history" => [ { "account_id" => "a1", "date" => "2026-09-30", "signedBalance" => 1.0 } ] },
      { "generated_at" => "2026-09-29T00:00:00Z" }
    )
    # The export timestamp wins over balance_history even when a later
    # balance row exists (Monarch syncs balances after the export run).
    assert_equal Date.new(2026, 9, 29), archive.as_of_date
  end

  test "as_of_date falls back to the newest balance_history date" do
    archive = build_archive(
      "balance_history" => [
        { "account_id" => "a1", "date" => "2026-03-01", "signedBalance" => 300.0 },
        { "account_id" => "a1", "date" => "2026-03-03", "signedBalance" => 500.0 }
      ]
    )
    assert_equal Date.new(2026, 3, 3), archive.as_of_date
  end

  test "as_of_date falls back to today with no VALIDATION and no balance_history" do
    archive = build_archive
    assert_equal Date.current, archive.as_of_date
  end

  test "as_of_date falls back when VALIDATION carries no usable timestamp" do
    archive = build_archive(
      { "balance_history" => [ { "account_id" => "a1", "date" => "2026-05-02", "signedBalance" => 1.0 } ] },
      { "generated_at" => "not-a-date" }
    )
    assert_equal Date.new(2026, 5, 2), archive.as_of_date
  end
end
