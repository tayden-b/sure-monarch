## Import rules

1. Treat every Monarch ID as an opaque string. IDs exceed JavaScript's safe integer range. Create a source-ID mapping instead of casting to Number.
2. Import category groups/categories, tags, accounts, merchants and goals before transactions; restore tag links, rules and recurring configuration afterward. Import balance history by `(account_id,date)` independently of transactions.
3. Preserve signs, nulls and original precision. Use decimal arithmetic for money. Keep currentBalance, displayBalance and signedBalance distinct. Do not invert liability balances twice or replace null balances with zero.
4. Preserve hidden/deactivated accounts and report/net-worth inclusion flags. There are 3 pending transactions: reconcile these with later posted records before merging future bank feeds. Do not indiscriminately deduplicate by amount/date/merchant; distinct transactions can match on those values.
5. Split-parent/child fields were requested, but no splits were returned. The archive also contains no transaction notes or attachments. Empty successful responses are distinct from denied/failed requests.
6. Daily net worth is a derived series. Recurring occurrences and budget actuals are not extra transactions. Portfolio performance points are calculated returns, not historical holdings or balance snapshots. Do not add these collections to ledger totals.
7. For fields that changed across source captures, consolidation preserves fuller nested objects and uses later selected values. Keep raw responses for provenance. All transaction IDs and checked ledger fields were stable across the two passes.

