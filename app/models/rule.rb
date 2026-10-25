class Rule < ApplicationRecord
  UnsupportedResourceTypeError = Class.new(StandardError)

  belongs_to :family
  has_many :conditions, dependent: :destroy
  has_many :actions, dependent: :destroy
  has_many :rule_runs, dependent: :destroy

  accepts_nested_attributes_for :conditions, allow_destroy: true
  accepts_nested_attributes_for :actions, allow_destroy: true

  # Rules execute in a user-defined order (Monarch parity): the lowest
  # `position` applies first. `id` breaks position ties so the order is always
  # deterministic, and rows without a position sort last (Postgres NULLS LAST).
  scope :ordered, -> { order(:position, :id) }

  before_validation :normalize_name
  before_create :assign_default_position

  validates :resource_type, presence: true
  validates :name, length: { minimum: 1 }, allow_nil: true
  validate :no_nested_compound_conditions

  # Every rule must have at least 1 action
  validate :min_actions
  validate :no_duplicate_actions

  def action_executors
    registry.action_executors
  end

  def condition_filters
    registry.condition_filters
  end

  def registry
    @registry ||= case resource_type
    when "transaction"
      Rule::Registry::TransactionResource.new(self)
    else
      raise UnsupportedResourceTypeError, "Unsupported resource type: #{resource_type}"
    end
  end

  def affected_resource_count
    matching_resources_scope.count
  end

  # Public wrapper around the private matching scope so callers can read the
  # currently-matching transaction ids WITHOUT running executors (e.g. the
  # notification baseline pre-seed). Mirrors total_affected_resource_count,
  # which also reaches matching_resources_scope.
  def matching_transaction_ids
    matching_resources_scope.pluck(:id)
  end

  # Creates a categorization rule for the Quick Categorize Wizard.
  # Returns the saved rule, or nil if a duplicate or invalid rule already exists.
  def self.create_from_grouping(family, grouping_key, category, transaction_type: nil)
    rule = family.rules.build(name: grouping_key, resource_type: "transaction", active: true)
    rule.conditions.build(condition_type: "transaction_name", operator: "like", value: grouping_key)
    rule.conditions.build(condition_type: "transaction_type", operator: "=", value: transaction_type) if transaction_type.present?
    rule.actions.build(action_type: "set_transaction_category", value: category.id.to_s)
    rule.save!
    rule
  rescue ActiveRecord::RecordInvalid
    nil
  end

  # Fresh tracker shared across an ordered batch apply. Maps a conflict key
  # (the field an action writes, e.g. :category_id) to the ids of transactions
  # already claimed for that field by an earlier-positioned rule.
  def self.new_claim_tracker
    Hash.new { |hash, key| hash[key] = Set.new }
  end

  # Persists a new ordering. Ids absent from ordered_ids keep their relative
  # order and move to the end, so a partial list can never drop or duplicate
  # rules. Positions are renumbered densely (1..n) to keep moves idempotent.
  def self.reorder!(family, ordered_ids)
    by_id = family.rules.index_by(&:id)
    ranked = Array(ordered_ids).filter_map { |id| by_id.delete(id.to_s) }
    remaining = by_id.values.sort_by { |rule| [ rule.position || Float::INFINITY, rule.id ] }

    transaction do
      (ranked + remaining).each_with_index do |rule, index|
        rule.update_column(:position, index + 1) if rule.position != index + 1
      end
    end
  end

  # Calculates total unique resources affected across multiple rules
  # This handles overlapping rules by deduplicating transaction IDs
  def self.total_affected_resource_count(rules)
    return 0 if rules.empty?

    # Collect all unique transaction IDs matched by any rule
    transaction_ids = Set.new
    rules.each do |rule|
      transaction_ids.merge(rule.send(:matching_resources_scope).pluck(:id))
    end

    transaction_ids.size
  end

  # Ordering semantics (Monarch parity): rules apply in `position` order and
  # the FIRST rule whose actions touch a field wins it — "first-match-wins
  # per field", not all-match-apply. When a shared `claimed_fields` tracker
  # (see Rule.new_claim_tracker) is passed by a batch apply, this rule claims
  # every field it writes for every transaction it matches, and its own
  # actions skip transactions an earlier rule already claimed for that field.
  # Non-conflicting actions (e.g. send_email_notification) and merging
  # actions (set_transaction_tags) are unaffected by claims. A standalone
  # apply (no tracker) always applies the whole rule.
  def apply(ignore_attribute_locks: false, rule_run: nil, claimed_fields: nil)
    total_modified = 0
    total_async_jobs = 0
    has_async = false

    claimed_conflict_keys = claimed_fields ? actions.filter_map(&:conflict_key).uniq : []
    # The claim set is the scope matched at this rule's turn, snapshotted
    # before its own actions mutate the matched fields.
    matched_ids = matching_transaction_ids if claimed_conflict_keys.any?

    actions.each do |action|
      scope = matching_resources_scope
      if claimed_fields && (key = action.conflict_key) && claimed_fields[key].any?
        scope = scope.where.not(transactions: { id: claimed_fields[key].to_a })
      end
      result = action.apply(scope, ignore_attribute_locks: ignore_attribute_locks, rule_run: rule_run)

      if result.is_a?(Hash) && result[:async]
        has_async = true
        total_async_jobs += result[:jobs_count] || 0
        total_modified += result[:modified_count] || 0
      elsif result.is_a?(Integer)
        total_modified += result
      else
        # Log unexpected result type but don't fail
        Rails.logger.warn("Rule#apply: Unexpected result type from action #{action.id}: #{result.class} (value: #{result.inspect})")
      end
    end

    claimed_conflict_keys.each { |key| claimed_fields[key].merge(matched_ids) } if claimed_fields

    if has_async
      { modified_count: total_modified, async: true, jobs_count: total_async_jobs }
    else
      total_modified
    end
  end

  # Moves the rule one slot up or down the ordered list. Returns false when
  # the move is out of range or the direction is invalid.
  def move(direction)
    ids = family.rules.ordered.pluck(:id)
    index = ids.index(id)
    return false if index.nil?

    target = direction == "up" ? index - 1 : index + 1
    return false if target.negative? || target >= ids.size

    ids.insert(target, ids.delete_at(index))
    self.class.reorder!(family, ids)
    true
  end

  def apply_later(ignore_attribute_locks: false)
    RuleJob.perform_later(self, ignore_attribute_locks: ignore_attribute_locks)
  end

  def primary_condition_title
    condition = displayed_condition
    return I18n.t("rules.no_condition") if condition.blank?

    "If #{condition.filter.label.downcase} #{condition.operator} #{condition.value_display}"
  end

  def displayed_condition
    displayable_conditions.first
  end

  def additional_displayable_conditions_count
    [ displayable_conditions.size - 1, 0 ].max
  end

  def displayable_conditions
    conditions.filter_map do |condition|
      condition.compound? ? condition.sub_conditions.first : condition
    end
  end

  private
    def matching_resources_scope
      scope = registry.resource_scope

      # 1. Prepare the query with joins required by conditions
      conditions.each do |condition|
        scope = condition.prepare(scope)
      end

      # 2. Apply the conditions to the query
      conditions.each do |condition|
        scope = condition.apply(scope)
      end

      scope
    end

    def min_actions
      return if new_record? && !actions.empty?

      if actions.reject(&:marked_for_destruction?).empty?
        errors.add(:base, :min_actions)
      end
    end

    def no_duplicate_actions
      action_types = actions.reject(&:marked_for_destruction?).map(&:action_type)

      errors.add(:base, :duplicate_actions, types: action_types.inspect) if action_types.uniq.count != action_types.count
    end

    # Validation: To keep rules simple and easy to understand, we don't allow nested compound conditions.
    def no_nested_compound_conditions
      return true if conditions.none? { |condition| condition.compound? }

      conditions.each do |condition|
        if condition.compound?
          if condition.sub_conditions.any? { |sub_condition| sub_condition.compound? }
            errors.add(:base, :nested_conditions)
          end
        end
      end
    end

    def normalize_name
      self.name = nil if name.is_a?(String) && name.strip.empty?
    end

    def assign_default_position
      self.position ||= (family&.rules&.maximum(:position) || 0) + 1
    end
end
