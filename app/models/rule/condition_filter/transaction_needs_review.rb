class Rule::ConditionFilter::TransactionNeedsReview < Rule::ConditionFilter
  def type
    "select"
  end

  def options
    [
      [ I18n.t("rules.condition_filters.transaction_needs_review.needs_review"), "needs_review" ],
      [ I18n.t("rules.condition_filters.transaction_needs_review.reviewed"), "reviewed" ]
    ]
  end

  def operators
    [ [ I18n.t("rules.condition_filters.transaction_needs_review.equal_to"), "=" ] ]
  end

  def apply(scope, operator, value)
    case value
    when "needs_review"
      scope.needs_review
    when "reviewed"
      scope.excluding_needs_review
    else
      scope
    end
  end
end
