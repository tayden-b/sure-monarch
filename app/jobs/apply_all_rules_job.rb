class ApplyAllRulesJob < ApplicationJob
  queue_as :medium_priority

  # Applies rules in `position` order sharing one claim tracker, so the first
  # (lowest-position) rule that touches a field wins it — Monarch semantics.
  # A failing rule is recorded on its own RuleRun by RuleJob and must not
  # starve the remaining rules, so the loop swallows the re-raised error.
  def perform(family, execution_type: "manual", active_only: false, ignore_attribute_locks: true)
    rules = family.rules.ordered
    rules = rules.where(active: true) if active_only

    claimed_fields = Rule.new_claim_tracker

    rules.each do |rule|
      RuleJob.perform_now(
        rule,
        ignore_attribute_locks: ignore_attribute_locks,
        execution_type: execution_type,
        claimed_fields: claimed_fields
      )
    rescue => e
      Rails.logger.error("ApplyAllRulesJob: rule #{rule.id} failed (#{e.class}: #{e.message}); continuing")
    end
  end
end
