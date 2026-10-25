require "test_helper"

class Dedup::NameNormalizerTest < ActiveSupport::TestCase
  test "strips common provider decorations" do
    assert_equal Dedup::NameNormalizer.call("SQ *JOE'S COFFEE"), Dedup::NameNormalizer.call("TST* Joe's Coffee")
    assert_equal Dedup::NameNormalizer.call("CHECKCARD 0423 NETFLIX.COM 888-555"), Dedup::NameNormalizer.call("netflix com")
  end

  test "blank and nil normalize to empty" do
    assert_equal "", Dedup::NameNormalizer.call(nil)
    assert_equal "", Dedup::NameNormalizer.call("   ")
  end

  test "similarity is 1.0 for normalized equality" do
    assert_equal 1.0, Dedup::NameNormalizer.similarity("SQ *Trader Joes #123", "TRADER JOES")
  end

  test "similarity scores token overlap" do
    score = Dedup::NameNormalizer.similarity("SQ *TRADER JOES", "Trader Joes Store 115")
    assert score > 0.0

    assert_equal 0.0, Dedup::NameNormalizer.similarity("Starbucks", "Shell Oil")
  end
end
