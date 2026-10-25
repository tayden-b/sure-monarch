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
