# Nets refunds within each category before arranging flows. Parent totals already
# include children: subtract those children before partitioning by direction, so
# a refund in a child cannot be counted again in its parent's net amount.
class IncomeStatement::Sankey
  def initialize(statement, period:)
    @statement, @period = statement, period
  end

  def as_json(*)
    @nodes, @links = [], []
    groups = category_groups
    income = groups.sum { |group| side_total(group, :income) }.to_d
    spending = groups.sum { |group| side_total(group, :expense) }.to_d
    # When the family counts contributions as expenses the money is already
    # inside the expense categories — a separate Investments branch would
    # double-count it, so the branch only exists in savings mode. A negative
    # net (more withdrawn than contributed) is folded back into surplus
    # rather than drawn as an inbound branch.
    invested = @statement.investments_as_savings? ? [ @statement.invested_totals(period: @period).net.to_d, 0 ].max : 0.to_d
    outflows = spending + invested
    capacity = [ income, outflows ].max
    unless capacity.zero?
      center = add_node("cash_flow_node", "Cash Flow", :cash_flow, capacity, 100)
      groups.each do |group|
        add_group(group, :income, income, center)
        add_group(group, :expense, outflows, center)
      end
      if invested.positive?
        index = add_node("investments_node", "Investments", :investments, invested, percentage(invested, outflows))
        add_link(center, index, invested, percentage(invested, outflows))
      end
      net = income - outflows
      unless net.zero?
        kind = net.positive? ? :surplus : :deficit
        index = add_node("#{kind}_node", kind.to_s.capitalize, kind, net.abs, percentage(net.abs, capacity))
        source, target = net.positive? ? [ center, index ] : [ index, center ]
        add_link(source, target, net.abs, percentage(net.abs, capacity))
      end
    end
    { basis: "net_by_category", income: decimal(income), spending: decimal(spending),
      invested: decimal(invested), net_savings: decimal(income - outflows), nodes: @nodes, links: @links }
  end

  private
    # Keep this hierarchy-aware netting separate from IncomeStatement#net_category_totals
    # while the original dashboard Sankey remains available for preview comparisons.
    def category_groups
      expense = @statement.expense_totals(period: @period).category_totals.index_by { |ct| category_key(ct.category) }
      income = @statement.income_totals(period: @period).category_totals.index_by { |ct| category_key(ct.category) }
      entries = (expense.keys | income.keys).sort.map do |key|
        category = (expense[key] || income[key]).category
        { category: category, net: (expense[key]&.total || 0).to_d - (income[key]&.total || 0).to_d }
      end
      children = entries.select { |entry| entry[:category].subcategory? }.group_by { |entry| entry[:category].parent_id }
      entries.reject { |entry| entry[:category].subcategory? }.map do |root|
        subs = children.fetch(root[:category].id, [])
        { category: root[:category], direct: root[:net] - subs.sum { |sub| sub[:net] }, children: subs }
      end
    end

    def category_key(category)
      return "uncategorized" if category.uncategorized?
      return "other_investments" if category.other_investments?
      category.id
    end

    def side_amount(net, side)
      [ side == :expense ? net : -net, 0 ].max
    end

    def side_total(group, side)
      side_amount(group[:direct], side) + group[:children].sum { |child| side_amount(child[:net], side) }
    end

    def add_group(group, side, total, center)
      amount = side_total(group, side)
      return if amount.zero?
      category = group[:category]
      pct = percentage(amount, total)
      root = add_node("#{side}_#{category_key(category)}", category.name, side, amount, pct, category)
      source, target = side == :income ? [ root, center ] : [ center, root ]
      add_link(source, target, amount, pct)
      group[:children].each do |child|
        value = side_amount(child[:net], side)
        next if value.zero?
        category = child[:category]
        pct = percentage(value, amount)
        index = add_node("#{side}_sub_#{category.id}", category.name, side, value, pct, category)
        source, target = side == :income ? [ index, root ] : [ root, index ]
        add_link(source, target, value, pct)
      end
    end

    def add_node(id, name, kind, value, percentage, category = nil)
      @nodes << { id: id, name: name, kind: kind.to_s, value: decimal(value), percentage: decimal(percentage),
        category_id: category&.id, filter_value: category && !category.other_investments? ? category.filter_value : nil,
        color: category&.color }
      @nodes.size - 1
    end

    def add_link(source, target, value, percentage)
      @links << { source: source, target: target, value: decimal(value), percentage: decimal(percentage) }
    end

    def percentage(value, total)
      total.zero? ? 0 : (value.to_d / total * 100).round(1)
    end

    def decimal(value)
      value.to_d.to_s("F")
    end
end
