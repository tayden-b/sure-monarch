require "test_helper"

class CategoryGroupTest < ActiveSupport::TestCase
  setup do
    @family = families(:empty)
  end

  test "requires name and a valid classification" do
    group = @family.category_groups.build(name: "")
    assert_not group.valid?
    assert_includes group.errors[:name], "can't be blank"

    group.name = "Everyday Expenses"
    group.classification = nil
    assert_not group.valid?

    group.classification = "bogus"
    assert_not group.valid?

    %w[income expense transfer].each do |classification|
      group.classification = classification
      assert group.valid?, "expected #{classification} to be valid"
    end
  end

  test "ordered scope puts positioned groups first, then unpositioned by name" do
    b = @family.category_groups.create!(name: "B", classification: "expense", position: 2)
    unpositioned = @family.category_groups.create!(name: "Zed", classification: "expense")
    a = @family.category_groups.create!(name: "A", classification: "income", position: 1)

    assert_equal [ a, b, unpositioned ], @family.category_groups.ordered.to_a
  end

  test "group classification is authoritative for members" do
    group = @family.category_groups.create!(name: "Income", classification: "income")
    category = @family.categories.create!(
      name: "Consulting", color: "#000000", lucide_icon: "briefcase",
      classification: "expense", category_group: group
    )

    assert_equal "income", category.classification
  end

  test "changing a group's classification syncs member categories and their subcategories" do
    group = @family.category_groups.create!(name: "Everyday", classification: "expense")
    parent = @family.categories.create!(name: "Food", color: "#000000", lucide_icon: "utensils", category_group: group)
    child = @family.categories.create!(name: "Groceries", color: "#111111", lucide_icon: "shopping-bag", parent: parent)

    assert_equal group, child.category_group
    assert_equal "expense", child.classification

    group.update!(classification: "transfer")

    assert_equal "transfer", parent.reload.classification
    assert_equal "transfer", child.reload.classification
  end

  test "destroying a group leaves its categories ungrouped" do
    group = @family.category_groups.create!(name: "Everyday", classification: "expense")
    category = @family.categories.create!(name: "Food", color: "#000000", lucide_icon: "utensils", category_group: group)

    group.destroy!

    assert_nil category.reload.category_group
    assert_equal "expense", category.classification
  end
end
