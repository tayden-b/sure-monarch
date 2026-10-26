namespace :monarch do
  desc "Import a Monarch Money export archive. " \
       "Usage: bin/rails \"monarch:import[/path/to/archive]\" (append ,dry_run or set DRY_RUN=1 for reconciliation only)"
  task :import, [ :archive_path, :mode ] => :environment do |_t, args|
    path = args[:archive_path]
    abort "Usage: bin/rails \"monarch:import[/path/to/archive]\"" if path.blank?

    dry_run = args[:mode] == "dry_run" || ENV["DRY_RUN"] == "1"

    family = ENV["FAMILY_ID"].present? ? Family.find(ENV["FAMILY_ID"]) : Family.first
    abort "No family found — set FAMILY_ID or create an account first." unless family

    puts "#{dry_run ? "[dry run] " : ""}Importing Monarch archive at #{path} into family #{family.id}"
    Monarch::Importer.new(family: family, archive_path: path, dry_run: dry_run).run
    puts "Done#{dry_run ? " (nothing was written)" : ""}."

    next if dry_run

    # Post-import pass: provider re-deliveries of archive rows are the main
    # duplicate source. The scan is read-only; merges happen in the UI.
    summary = Dedup::Scanner.new(family: family).summary
    if summary[:total].positive?
      puts "#{summary[:total]} duplicate candidate pair(s) found — review and merge at http://localhost:3000/dedup/candidates"
      puts "(run `bin/rails monarch:dedup` for a per-account breakdown)"
    else
      puts "No duplicate candidates found."
    end
  end

  desc "Scan the family ledger for cross-source duplicate transactions and print where to review them. " \
       "Usage: bin/rails monarch:dedup (optional: ACCOUNT_ID=..., DATE_WINDOW=5, LIMIT=500, INCLUDE_DISMISSED=1, SAME_SOURCE=1)"
  task dedup: :environment do
    family = ENV["FAMILY_ID"].present? ? Family.find(ENV["FAMILY_ID"]) : Family.first
    abort "No family found — set FAMILY_ID or create an account first." unless family

    scanner = Dedup::Scanner.new(
      family: family,
      account: ENV["ACCOUNT_ID"].present? ? family.accounts.find(ENV["ACCOUNT_ID"]) : nil,
      date_window: (ENV["DATE_WINDOW"] || Dedup::Scanner::DEFAULT_DATE_WINDOW).to_i,
      limit: (ENV["LIMIT"] || Dedup::Scanner::DEFAULT_LIMIT).to_i,
      include_dismissed: ENV["INCLUDE_DISMISSED"] == "1",
      include_same_source: ENV["SAME_SOURCE"] == "1"
    )
    summary = scanner.summary

    puts "#{summary[:total]} duplicate candidate pair(s) " \
         "(+/-#{scanner.date_window}d window, cap #{scanner.limit}):"
    %i[high medium low].each do |level|
      count = summary[:by_confidence][level].to_i
      puts "  #{level} confidence: #{count}" if count.positive?
    end
    summary[:by_account].sort.each do |name, count|
      puts "  #{name}: #{count} pair(s)"
    end
    puts "Review and merge at http://localhost:3000/dedup/candidates" if summary[:total].positive?
  end

  desc "Delete every record created by a Monarch import (via monarch_source_mappings)"
  task revert: :environment do
    family = ENV["FAMILY_ID"].present? ? Family.find(ENV["FAMILY_ID"]) : Family.first
    abort "No family found — set FAMILY_ID or create an account first." unless family

    puts "Reverting Monarch import for family #{family.id}"
    Monarch::Reverter.new(family: family).run
    puts "Done."
  end
end
