class Rule::ActionExecutor::SetNeedsReview < Rule::ActionExecutor
  def type
    "select"
  end

  def options
    [
      [ I18n.t("rules.action_executors.set_needs_review.needs_review"), "needs_review" ],
      [ I18n.t("rules.action_executors.set_needs_review.reviewed"), "reviewed" ]
    ]
  end

  def execute(transaction_scope, value: nil, ignore_attribute_locks: false, rule_run: nil)
    return 0 unless %w[needs_review reviewed].include?(value)

    flag = value == "needs_review"

    # Direct update, not enrich_attribute: needs_review is workflow state the
    # user resolves by hand, so it isn't tracked in locked_attributes and a
    # rule-set flag must not protect the row from provider sync.
    count_modified_resources(transaction_scope) do |txn|
      if txn.needs_review? == flag
        false
      else
        txn.update!(needs_review: flag)
        true
      end
    end
  end
end
