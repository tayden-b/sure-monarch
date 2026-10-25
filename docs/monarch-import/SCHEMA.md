# Monarch export — schema reference (structure only, no values)

Generated from Tayden's private Monarch archive (2026-09-29). This file lists key paths and observed JSON types only. **The real archive never leaves his machine** — build and test the importer against synthetic fixtures that match these shapes.

Top-level layout of the archive directory the importer must accept:
```
README.md  VALIDATION.json  monarch.sqlite
import/<collection>.json   # consolidated, import-ready (PREFER THESE)
csv/<collection>.csv       # same collections, nested fields as JSON text
raw/ requests/ normalized/ errors/ failed_attempts/ attachments/
```

`monarch.sqlite` has `records(collection, record_key, payload_json)`, `raw_documents(path, payload_json)` and views `transactions`, `accounts`, `balance_history`.


## import/accounts.json  (top-level list, 25 entries)

| key path | types seen |
|---|---|
| `[]` | dict×25 |
| `[].__typename` | str×25 |
| `[].apr` | NoneType×25 |
| `[].businessEntity` | NoneType×25 |
| `[].canInvertBalance` | bool×25 |
| `[].canUseAvailableBalance` | bool×25 |
| `[].connectionStatus` | NoneType×24, dict×1 |
| `[].connectionStatus.connectionStatusCode` | str×1 |
| `[].createdAt` | str×25 |
| `[].credential` | dict×25 |
| `[].credential.__typename` | str×25 |
| `[].credential.canBeForceRefreshed` | bool×25 |
| `[].credential.dataProvider` | str×25 |
| `[].credential.disconnectedFromDataProviderAt` | NoneType×25 |
| `[].credential.hasSyncInProgress` | bool×25 |
| `[].credential.id` | str×25 |
| `[].credential.institution` | dict×25 |
| `[].credential.institution.__typename` | str×25 |
| `[].credential.institution.balanceStatus` | NoneType×25 |
| `[].credential.institution.hasIssuesReported` | bool×25 |
| `[].credential.institution.hasIssuesReportedMessage` | str×25 |
| `[].credential.institution.id` | str×25 |
| `[].credential.institution.logo` | str×25 |
| `[].credential.institution.name` | str×25 |
| `[].credential.institution.newConnectionsDisabled` | bool×25 |
| `[].credential.institution.plaidInstitutionId` | str×24, NoneType×1 |
| `[].credential.institution.plaidStatus` | dict×20, NoneType×5 |
| `[].credential.institution.plaidStatus.auth` | dict×17 |
| `[].credential.institution.plaidStatus.auth.breakdown` | dict×17 |
| `[].credential.institution.plaidStatus.auth.last_status_change` | str×17 |
| `[].credential.institution.plaidStatus.auth.status` | str×17 |
| `[].credential.institution.plaidStatus.health_incidents` | list×12 |
| `[].credential.institution.plaidStatus.health_incidents[]` | dict×90 |
| `[].credential.institution.plaidStatus.identity` | dict×17 |
| `[].credential.institution.plaidStatus.identity.breakdown` | dict×17 |
| `[].credential.institution.plaidStatus.identity.last_status_change` | str×17 |
| `[].credential.institution.plaidStatus.identity.status` | str×17 |
| `[].credential.institution.plaidStatus.investments` | dict×13 |
| `[].credential.institution.plaidStatus.investments.breakdown` | dict×13 |
| `[].credential.institution.plaidStatus.investments.last_status_change` | str×13 |
| `[].credential.institution.plaidStatus.investments.status` | str×13 |
| `[].credential.institution.plaidStatus.investments_updates` | dict×19 |
| `[].credential.institution.plaidStatus.investments_updates.breakdown` | dict×19 |
| `[].credential.institution.plaidStatus.investments_updates.last_status_change` | str×19 |
| `[].credential.institution.plaidStatus.investments_updates.status` | str×19 |
| `[].credential.institution.plaidStatus.item_logins` | dict×19, NoneType×1 |
| `[].credential.institution.plaidStatus.item_logins.breakdown` | dict×19 |
| `[].credential.institution.plaidStatus.item_logins.last_status_change` | str×19 |
| `[].credential.institution.plaidStatus.item_logins.status` | str×19 |
| `[].credential.institution.plaidStatus.liabilities` | dict×5 |
| `[].credential.institution.plaidStatus.liabilities.breakdown` | dict×5 |
| `[].credential.institution.plaidStatus.liabilities.last_status_change` | str×5 |
| `[].credential.institution.plaidStatus.liabilities.status` | str×5 |
| `[].credential.institution.plaidStatus.liabilities_updates` | dict×14 |
| `[].credential.institution.plaidStatus.liabilities_updates.breakdown` | dict×14 |
| `[].credential.institution.plaidStatus.liabilities_updates.last_status_change` | str×14 |
| `[].credential.institution.plaidStatus.liabilities_updates.status` | str×14 |
| `[].credential.institution.plaidStatus.transactions_updates` | dict×19 |
| `[].credential.institution.plaidStatus.transactions_updates.breakdown` | dict×19 |
| `[].credential.institution.plaidStatus.transactions_updates.last_status_change` | str×19 |
| `[].credential.institution.plaidStatus.transactions_updates.status` | str×19 |
| `[].credential.institution.status` | str×19, NoneType×6 |
| `[].credential.institution.transactionsStatus` | str×19, NoneType×6 |
| `[].credential.institution.url` | str×25 |
| `[].credential.syncDisabledAt` | NoneType×25 |
| `[].credential.syncDisabledReason` | NoneType×25 |
| `[].credential.updateRequired` | bool×25 |
| `[].creditReportLiabilityAccount` | NoneType×25 |
| `[].currentBalance` | float×23, NoneType×2 |
| `[].dataProvider` | str×25 |
| `[].dataProviderAccountId` | str×25 |
| `[].dataProviderCreditLimit` | NoneType×20, float×5 |
| `[].dataProviderDeactivatedAt` | NoneType×24, str×1 |
| `[].dataProviderInterestRateType` | NoneType×25 |
| `[].deactivatedAt` | NoneType×24, str×1 |
| `[].displayBalance` | float×24, NoneType×1 |
| `[].displayLastUpdatedAt` | str×25 |
| `[].displayName` | str×25 |
| `[].excludeFromDebtPaydown` | bool×25 |
| `[].hasCustomizedLogo` | bool×25 |
| `[].hideFromList` | bool×25 |
| `[].hideInBudget` | bool×25 |
| `[].hideTransactionsFromReports` | bool×25 |
| `[].holdingsCount` | int×25 |
| `[].icon` | str×25 |
| `[].id` | str×25 |
| `[].includeBalanceInNetWorth` | bool×25 |
| `[].includeInGoalBalance` | bool×25 |
| `[].includeInNetWorth` | bool×25 |
| `[].institution` | dict×25 |
| `[].institution.__typename` | str×25 |
| `[].institution.balanceStatus` | NoneType×25 |
| `[].institution.hasIssuesReported` | bool×25 |
| `[].institution.hasIssuesReportedMessage` | str×25 |
| `[].institution.id` | str×25 |
| `[].institution.logo` | str×25 |
| `[].institution.name` | str×25 |
| `[].institution.plaidInstitutionId` | str×24, NoneType×1 |
| `[].institution.plaidStatus` | dict×20, NoneType×5 |
| `[].institution.plaidStatus.auth` | dict×17 |
| `[].institution.plaidStatus.auth.breakdown` | dict×17 |
| `[].institution.plaidStatus.auth.breakdown.error_institution` | int×14, float×3 |
| `[].institution.plaidStatus.auth.breakdown.error_plaid` | float×9, int×8 |
| `[].institution.plaidStatus.auth.breakdown.success` | float×12, int×5 |
| `[].institution.plaidStatus.auth.last_status_change` | str×17 |
| `[].institution.plaidStatus.auth.status` | str×17 |
| `[].institution.plaidStatus.health_incidents` | list×12 |
| `[].institution.plaidStatus.health_incidents[]` | dict×90 |
| `[].institution.plaidStatus.health_incidents[].end_date` | str×90 |
| `[].institution.plaidStatus.health_incidents[].incident_updates` | list×90 |
| `[].institution.plaidStatus.health_incidents[].start_date` | str×90 |
| `[].institution.plaidStatus.health_incidents[].title` | str×90 |
| `[].institution.plaidStatus.identity` | dict×17 |
| `[].institution.plaidStatus.identity.breakdown` | dict×17 |
| `[].institution.plaidStatus.identity.breakdown.error_institution` | int×14, float×3 |
| `[].institution.plaidStatus.identity.breakdown.error_plaid` | int×17 |
| `[].institution.plaidStatus.identity.breakdown.success` | int×14, float×3 |
| `[].institution.plaidStatus.identity.last_status_change` | str×17 |
| `[].institution.plaidStatus.identity.status` | str×17 |
| `[].institution.plaidStatus.investments` | dict×13 |
| `[].institution.plaidStatus.investments.breakdown` | dict×13 |
| `[].institution.plaidStatus.investments.breakdown.error_institution` | int×12, float×1 |
| `[].institution.plaidStatus.investments.breakdown.error_plaid` | int×13 |
| `[].institution.plaidStatus.investments.breakdown.success` | int×12, float×1 |
| `[].institution.plaidStatus.investments.last_status_change` | str×13 |
| `[].institution.plaidStatus.investments.status` | str×13 |
| `[].institution.plaidStatus.investments_updates` | dict×19 |
| `[].institution.plaidStatus.investments_updates.breakdown` | dict×19 |
| `[].institution.plaidStatus.investments_updates.breakdown.error_institution` | float×12, int×7 |
| `[].institution.plaidStatus.investments_updates.breakdown.error_plaid` | int×14, float×5 |
| `[].institution.plaidStatus.investments_updates.breakdown.refresh_interval` | str×19 |
| `[].institution.plaidStatus.investments_updates.breakdown.success` | float×18, int×1 |
| `[].institution.plaidStatus.investments_updates.last_status_change` | str×19 |
| `[].institution.plaidStatus.investments_updates.status` | str×19 |
| `[].institution.plaidStatus.item_logins` | dict×19, NoneType×1 |
| `[].institution.plaidStatus.item_logins.breakdown` | dict×19 |
| `[].institution.plaidStatus.item_logins.breakdown.error_institution` | float×18, int×1 |
| `[].institution.plaidStatus.item_logins.breakdown.error_plaid` | float×13, int×6 |
| `[].institution.plaidStatus.item_logins.breakdown.success` | float×19 |
| `[].institution.plaidStatus.item_logins.last_status_change` | str×19 |
| `[].institution.plaidStatus.item_logins.status` | str×19 |
| `[].institution.plaidStatus.liabilities` | dict×5 |
| `[].institution.plaidStatus.liabilities.breakdown` | dict×5 |
| `[].institution.plaidStatus.liabilities.breakdown.error_institution` | int×5 |
| `[].institution.plaidStatus.liabilities.breakdown.error_plaid` | int×5 |
| `[].institution.plaidStatus.liabilities.breakdown.success` | int×5 |
| `[].institution.plaidStatus.liabilities.last_status_change` | str×5 |
| `[].institution.plaidStatus.liabilities.status` | str×5 |
| `[].institution.plaidStatus.liabilities_updates` | dict×14 |
| `[].institution.plaidStatus.liabilities_updates.breakdown` | dict×14 |
| `[].institution.plaidStatus.liabilities_updates.breakdown.error_institution` | float×9, int×5 |
| `[].institution.plaidStatus.liabilities_updates.breakdown.error_plaid` | int×14 |
| `[].institution.plaidStatus.liabilities_updates.breakdown.refresh_interval` | str×14 |
| `[].institution.plaidStatus.liabilities_updates.breakdown.success` | float×9, int×5 |
| `[].institution.plaidStatus.liabilities_updates.last_status_change` | str×14 |
| `[].institution.plaidStatus.liabilities_updates.status` | str×14 |
| `[].institution.plaidStatus.transactions_updates` | dict×19 |
| `[].institution.plaidStatus.transactions_updates.breakdown` | dict×19 |
| `[].institution.plaidStatus.transactions_updates.breakdown.error_institution` | float×11, int×8 |
| `[].institution.plaidStatus.transactions_updates.breakdown.error_plaid` | int×13, float×6 |
| `[].institution.plaidStatus.transactions_updates.breakdown.refresh_interval` | str×19 |
| `[].institution.plaidStatus.transactions_updates.breakdown.success` | float×19 |
| `[].institution.plaidStatus.transactions_updates.last_status_change` | str×19 |
| `[].institution.plaidStatus.transactions_updates.status` | str×19 |
| `[].institution.primaryColor` | str×25 |
| `[].institution.status` | str×19, NoneType×6 |
| `[].institution.transactionsStatus` | str×19, NoneType×6 |
| `[].institution.url` | str×25 |
| `[].interestRate` | NoneType×25 |
| `[].interestRateType` | NoneType×25 |
| `[].invertSyncedBalance` | bool×25 |
| `[].isAsset` | bool×25 |
| `[].isHidden` | bool×25 |
| `[].isLiability` | bool×25 |
| `[].isManual` | bool×25 |
| `[].limit` | NoneType×20, float×5 |
| `[].logoUrl` | str×25 |
| `[].manualInvestmentsTrackingMethod` | NoneType×25 |
| `[].mask` | str×22, NoneType×3 |
| `[].minimumPayment` | NoneType×23, float×2 |
| `[].notes` | NoneType×25 |
| `[].order` | int×25 |
| `[].originalProviderData` | dict×14, NoneType×11 |
| `[].originalProviderData.apr` | NoneType×14 |
| `[].originalProviderData.interestRate` | NoneType×14 |
| `[].originalProviderData.minimumPayment` | NoneType×12, float×2 |
| `[].ownedByUser` | NoneType×25 |
| `[].plannedPayment` | NoneType×25 |
| `[].subtype` | dict×25 |
| `[].subtype.__typename` | str×25 |
| `[].subtype.display` | str×25 |
| `[].subtype.name` | str×25 |
| `[].syncDisabled` | bool×25 |
| `[].transactionsCount` | int×25 |
| `[].type` | dict×25 |
| `[].type.__typename` | str×25 |
| `[].type.display` | str×25 |
| `[].type.group` | str×25 |
| `[].type.name` | str×25 |
| `[].updatedAt` | str×25 |
| `[].useAvailableBalance` | NoneType×24, bool×1 |

## import/aggregate_holdings.json  (top-level list, 42 entries)

| key path | types seen |
|---|---|
| `[]` | dict×42 |
| `[].__typename` | str×42 |
| `[].account_id` | str×42 |
| `[].basis` | float×42 |
| `[].costBasis` | float×42 |
| `[].holdings` | list×42 |
| `[].holdings[]` | dict×42 |
| `[].holdings[].__typename` | str×42 |
| `[].holdings[].account` | dict×42 |
| `[].holdings[].account.currentBalance` | float×36, NoneType×6 |
| `[].holdings[].account.displayName` | str×42 |
| `[].holdings[].account.icon` | str×42 |
| `[].holdings[].account.id` | str×42 |
| `[].holdings[].account.institution` | dict×42 |
| `[].holdings[].account.institution.id` | str×42 |
| `[].holdings[].account.institution.name` | str×42 |
| `[].holdings[].account.logoUrl` | str×42 |
| `[].holdings[].account.mask` | str×32, NoneType×10 |
| `[].holdings[].account.order` | int×42 |
| `[].holdings[].account.subtype` | dict×42 |
| `[].holdings[].account.subtype.display` | str×42 |
| `[].holdings[].account.subtype.name` | str×42 |
| `[].holdings[].account.type` | dict×42 |
| `[].holdings[].account.type.display` | str×42 |
| `[].holdings[].account.type.name` | str×42 |
| `[].holdings[].allocationCategoryWeights` | list×42 |
| `[].holdings[].allocationCategoryWeights[]` | dict×178 |
| `[].holdings[].allocationCategoryWeights[].category` | dict×178 |
| `[].holdings[].allocationCategoryWeights[].weight` | float×178 |
| `[].holdings[].closingPrice` | float×36, NoneType×6 |
| `[].holdings[].closingPriceUpdatedAt` | NoneType×38, str×4 |
| `[].holdings[].costBasis` | float×33, NoneType×9 |
| `[].holdings[].holdingClassification` | NoneType×42 |
| `[].holdings[].id` | str×42 |
| `[].holdings[].isManual` | bool×42 |
| `[].holdings[].name` | str×42 |
| `[].holdings[].quantity` | float×42 |
| `[].holdings[].securityClassification` | NoneType×42 |
| `[].holdings[].taxLots` | list×42 |
| `[].holdings[].ticker` | str×40, NoneType×2 |
| `[].holdings[].type` | str×42 |
| `[].holdings[].typeDisplay` | str×42 |
| `[].holdings[].userCostBasis` | NoneType×42 |
| `[].holdings[].value` | float×42 |
| `[].id` | str×42 |
| `[].lastSyncedAt` | str×36, NoneType×6 |
| `[].quantity` | float×42 |
| `[].security` | dict×42 |
| `[].security.__typename` | str×42 |
| `[].security.assetClass` | str×42 |
| `[].security.closingPrice` | float×42 |
| `[].security.closingPriceUpdatedAt` | str×40, NoneType×2 |
| `[].security.currentPrice` | float×39, NoneType×3 |
| `[].security.currentPriceUpdatedAt` | str×39, NoneType×3 |
| `[].security.id` | str×42 |
| `[].security.name` | str×42 |
| `[].security.oneDayChangeDollars` | float×38, NoneType×4 |
| `[].security.oneDayChangePercent` | float×38, NoneType×4 |
| `[].security.ticker` | str×40, NoneType×2 |
| `[].security.type` | str×42 |
| `[].security.typeDisplay` | str×42 |
| `[].securityPriceChangeDollars` | float×36, NoneType×6 |
| `[].securityPriceChangePercent` | float×36, NoneType×6 |
| `[].totalValue` | float×42 |

## import/attachments.json  (top-level list, 0 entries)

| key path | types seen |
|---|---|

## import/balance_history.json  (top-level list, 8153 entries)

| key path | types seen |
|---|---|
| `[]` | dict×200 |
| `[].__typename` | str×200 |
| `[].account_id` | str×200 |
| `[].date` | str×200 |
| `[].signedBalance` | float×200 |

## import/budget_months.json  (top-level list, 8532 entries)

| key path | types seen |
|---|---|
| `[]` | dict×200 |
| `[].actualAmount` | float×200 |
| `[].cumulativeActualAmount` | float×200 |
| `[].entity_id` | str×200 |
| `[].month` | str×200 |
| `[].plannedCashFlowAmount` | float×200 |
| `[].plannedSetAsideAmount` | float×200 |
| `[].previousMonthRolloverAmount` | NoneType×200 |
| `[].remainingAmount` | float×200 |
| `[].rolloverTargetAmount` | NoneType×200 |
| `[].rolloverType` | NoneType×200 |
| `[].scope` | str×200 |

## import/budget_totals.json  (top-level list, 108 entries)

| key path | types seen |
|---|---|
| `[]` | dict×108 |
| `[].month` | str×108 |
| `[].totalExpenses` | dict×108 |
| `[].totalExpenses.actualAmount` | float×108 |
| `[].totalExpenses.plannedAmount` | float×108 |
| `[].totalExpenses.previousMonthRolloverAmount` | float×108 |
| `[].totalExpenses.remainingAmount` | float×108 |
| `[].totalFixedExpenses` | dict×108 |
| `[].totalFixedExpenses.actualAmount` | float×108 |
| `[].totalFixedExpenses.plannedAmount` | float×108 |
| `[].totalFixedExpenses.previousMonthRolloverAmount` | float×108 |
| `[].totalFixedExpenses.remainingAmount` | float×108 |
| `[].totalFlexibleExpenses` | dict×108 |
| `[].totalFlexibleExpenses.actualAmount` | float×108 |
| `[].totalFlexibleExpenses.plannedAmount` | float×108 |
| `[].totalFlexibleExpenses.previousMonthRolloverAmount` | float×108 |
| `[].totalFlexibleExpenses.remainingAmount` | float×108 |
| `[].totalIncome` | dict×108 |
| `[].totalIncome.actualAmount` | float×108 |
| `[].totalIncome.plannedAmount` | float×108 |
| `[].totalIncome.previousMonthRolloverAmount` | float×108 |
| `[].totalIncome.remainingAmount` | float×108 |
| `[].totalNonMonthlyExpenses` | dict×108 |
| `[].totalNonMonthlyExpenses.actualAmount` | float×108 |
| `[].totalNonMonthlyExpenses.plannedAmount` | float×108 |
| `[].totalNonMonthlyExpenses.previousMonthRolloverAmount` | float×108 |
| `[].totalNonMonthlyExpenses.remainingAmount` | float×108 |

## import/categories.json  (top-level list, 63 entries)

| key path | types seen |
|---|---|
| `[]` | dict×63 |
| `[].__typename` | str×63 |
| `[].budgetVariability` | str×63 |
| `[].createdAt` | str×63 |
| `[].excludeFromBudget` | bool×63 |
| `[].group` | dict×63 |
| `[].group.budgetVariability` | NoneType×63 |
| `[].group.groupLevelBudgetingEnabled` | bool×63 |
| `[].group.id` | str×63 |
| `[].group.name` | str×63 |
| `[].group.order` | int×63 |
| `[].group.type` | str×63 |
| `[].icon` | str×63 |
| `[].id` | str×63 |
| `[].isDisabled` | bool×63 |
| `[].isProtected` | bool×63 |
| `[].isSystemCategory` | bool×63 |
| `[].name` | str×63 |
| `[].order` | int×63 |
| `[].rolloverPeriod` | NoneType×63 |
| `[].systemCategory` | str×60, NoneType×3 |
| `[].systemCategoryDisplayName` | str×60, NoneType×3 |
| `[].updatedAt` | str×63 |

## import/category_groups.json  (top-level list, 15 entries)

| key path | types seen |
|---|---|
| `[]` | dict×15 |
| `[].__typename` | str×15 |
| `[].budgetVariability` | NoneType×15 |
| `[].categories` | list×15 |
| `[].categories[]` | dict×63 |
| `[].categories[].id` | str×63 |
| `[].color` | str×11, NoneType×4 |
| `[].groupLevelBudgetingEnabled` | bool×15 |
| `[].id` | str×15 |
| `[].name` | str×15 |
| `[].order` | int×15 |
| `[].rolloverPeriod` | NoneType×15 |
| `[].type` | str×15 |

## import/credit_scores.json  (top-level list, 11 entries)

| key path | types seen |
|---|---|
| `[]` | dict×11 |
| `[].__typename` | str×11 |
| `[].reportedDate` | str×11 |
| `[].score` | int×11 |
| `[].user` | dict×11 |
| `[].user.__typename` | str×11 |
| `[].user.id` | str×11 |

## import/equity_grants.json  (top-level list, 0 entries)

| key path | types seen |
|---|---|

## import/goals.json  (top-level list, 1 entries)

| key path | types seen |
|---|---|
| `[]` | dict×1 |
| `[].accountAllocations` | list×1 |
| `[].accountAllocations[]` | dict×10 |
| `[].accountAllocations[].account` | dict×10 |
| `[].accountAllocations[].account.currentBalance` | float×10 |
| `[].accountAllocations[].account.dataProvider` | str×10 |
| `[].accountAllocations[].account.deactivatedAt` | NoneType×10 |
| `[].accountAllocations[].account.displayBalance` | float×10 |
| `[].accountAllocations[].account.displayName` | str×10 |
| `[].accountAllocations[].account.hideFromList` | bool×10 |
| `[].accountAllocations[].account.icon` | str×10 |
| `[].accountAllocations[].account.id` | str×10 |
| `[].accountAllocations[].account.institution` | dict×10 |
| `[].accountAllocations[].account.institution.id` | str×10 |
| `[].accountAllocations[].account.institution.logo` | str×10 |
| `[].accountAllocations[].account.institution.primaryColor` | str×10 |
| `[].accountAllocations[].account.logoUrl` | str×10 |
| `[].accountAllocations[].account.mask` | str×10 |
| `[].accountAllocations[].account.subtype` | dict×10 |
| `[].accountAllocations[].account.subtype.display` | str×10 |
| `[].accountAllocations[].account.subtype.name` | str×10 |
| `[].accountAllocations[].account.type` | dict×10 |
| `[].accountAllocations[].account.type.display` | str×10 |
| `[].accountAllocations[].account.type.name` | str×10 |
| `[].accountAllocations[].amount` | NoneType×10 |
| `[].accountAllocations[].currentAmount` | float×10 |
| `[].accountAllocations[].currentMonthChange` | dict×10 |
| `[].accountAllocations[].currentMonthChange.amount` | float×10 |
| `[].accountAllocations[].currentMonthChange.percent` | float×10 |
| `[].accountAllocations[].id` | str×10 |
| `[].accountAllocations[].useEntireAccountBalance` | bool×10 |
| `[].archivedAt` | NoneType×1 |
| `[].completedAt` | NoneType×1 |
| `[].completionPercent` | float×1 |
| `[].currentAmount` | float×1 |
| `[].defaultName` | str×1 |
| `[].eligibleAccounts` | list×1 |
| `[].eligibleAccounts[]` | dict×18 |
| `[].eligibleAccounts[].availableBalanceForGoals` | float×18 |
| `[].eligibleAccounts[].dataProvider` | str×18 |
| `[].eligibleAccounts[].deactivatedAt` | NoneType×18 |
| `[].eligibleAccounts[].displayBalance` | float×18 |
| `[].eligibleAccounts[].displayName` | str×18 |
| `[].eligibleAccounts[].goalAllocations` | list×18 |
| `[].eligibleAccounts[].goalAllocations[]` | dict×10 |
| `[].eligibleAccounts[].goalAllocations[].amount` | NoneType×10 |
| `[].eligibleAccounts[].goalAllocations[].currentAmount` | float×10 |
| `[].eligibleAccounts[].goalAllocations[].goal` | dict×10 |
| `[].eligibleAccounts[].goalAllocations[].id` | str×10 |
| `[].eligibleAccounts[].goalAllocations[].useEntireAccountBalance` | bool×10 |
| `[].eligibleAccounts[].hideFromList` | bool×18 |
| `[].eligibleAccounts[].icon` | str×18 |
| `[].eligibleAccounts[].id` | str×18 |
| `[].eligibleAccounts[].institution` | dict×18 |
| `[].eligibleAccounts[].institution.id` | str×18 |
| `[].eligibleAccounts[].institution.logo` | str×18 |
| `[].eligibleAccounts[].institution.primaryColor` | str×18 |
| `[].eligibleAccounts[].isAsset` | bool×18 |
| `[].eligibleAccounts[].logoUrl` | str×18 |
| `[].eligibleAccounts[].subtype` | dict×18 |
| `[].eligibleAccounts[].subtype.name` | str×18 |
| `[].eligibleAccounts[].type` | dict×18 |
| `[].eligibleAccounts[].type.display` | str×18 |
| `[].eligibleAccounts[].type.name` | str×18 |
| `[].estimatedCompletionMonth` | NoneType×1 |
| `[].id` | str×1 |
| `[].imageStorageProvider` | str×1 |
| `[].imageStorageProviderId` | str×1 |
| `[].monthlyContributionSummaries` | list×1 |
| `[].monthlyContributionSummaries[]` | dict×109 |
| `[].monthlyContributionSummaries[].month` | str×109 |
| `[].monthlyContributionSummaries[].plannedAmount` | NoneType×109 |
| `[].monthlyContributionSummaries[].sum` | float×109 |
| `[].monthlyContributionSummaries[].sumCredit` | float×109 |
| `[].monthlyContributionSummaries[].sumDebit` | float×109 |
| `[].name` | str×1 |
| `[].newGoalId` | NoneType×1 |
| `[].objective` | str×1 |
| `[].plannedContributions` | list×1 |
| `[].plannedMonthlyContribution` | NoneType×1 |
| `[].plannedMonthlyPretaxContribution` | NoneType×1 |
| `[].priority` | int×1 |
| `[].startingAmount` | NoneType×1 |
| `[].suggestedAccounts` | list×1 |
| `[].suggestedAccounts[]` | dict×9 |
| `[].suggestedAccounts[].availableBalanceForGoals` | float×9 |
| `[].suggestedAccounts[].dataProvider` | str×9 |
| `[].suggestedAccounts[].deactivatedAt` | NoneType×9 |
| `[].suggestedAccounts[].displayBalance` | float×9 |
| `[].suggestedAccounts[].displayName` | str×9 |
| `[].suggestedAccounts[].goalAllocations` | list×9 |
| `[].suggestedAccounts[].goalAllocations[]` | dict×7 |
| `[].suggestedAccounts[].goalAllocations[].amount` | NoneType×7 |
| `[].suggestedAccounts[].goalAllocations[].currentAmount` | float×7 |
| `[].suggestedAccounts[].goalAllocations[].goal` | dict×7 |
| `[].suggestedAccounts[].goalAllocations[].id` | str×7 |
| `[].suggestedAccounts[].goalAllocations[].useEntireAccountBalance` | bool×7 |
| `[].suggestedAccounts[].hideFromList` | bool×9 |
| `[].suggestedAccounts[].icon` | str×9 |
| `[].suggestedAccounts[].id` | str×9 |
| `[].suggestedAccounts[].institution` | dict×9 |
| `[].suggestedAccounts[].institution.id` | str×9 |
| `[].suggestedAccounts[].institution.logo` | str×9 |
| `[].suggestedAccounts[].institution.primaryColor` | str×9 |
| `[].suggestedAccounts[].isAsset` | bool×9 |
| `[].suggestedAccounts[].logoUrl` | str×9 |
| `[].suggestedAccounts[].subtype` | dict×9 |
| `[].suggestedAccounts[].subtype.name` | str×9 |
| `[].suggestedAccounts[].type` | dict×9 |
| `[].suggestedAccounts[].type.display` | str×9 |
| `[].suggestedAccounts[].type.name` | str×9 |
| `[].targetAmount` | float×1 |
| `[].type` | str×1 |

## import/holdings.json  (top-level list, 42 entries)

| key path | types seen |
|---|---|
| `[]` | dict×42 |
| `[].__typename` | str×42 |
| `[].account` | dict×42 |
| `[].account.currentBalance` | float×36, NoneType×6 |
| `[].account.displayName` | str×42 |
| `[].account.icon` | str×42 |
| `[].account.id` | str×42 |
| `[].account.institution` | dict×42 |
| `[].account.institution.id` | str×42 |
| `[].account.institution.name` | str×42 |
| `[].account.logoUrl` | str×42 |
| `[].account.mask` | str×32, NoneType×10 |
| `[].account.order` | int×42 |
| `[].account.subtype` | dict×42 |
| `[].account.subtype.display` | str×42 |
| `[].account.subtype.name` | str×42 |
| `[].account.type` | dict×42 |
| `[].account.type.display` | str×42 |
| `[].account.type.name` | str×42 |
| `[].account_id` | str×42 |
| `[].aggregate_holding_id` | str×42 |
| `[].allocationCategoryWeights` | list×42 |
| `[].allocationCategoryWeights[]` | dict×178 |
| `[].allocationCategoryWeights[].category` | dict×178 |
| `[].allocationCategoryWeights[].category.id` | str×178 |
| `[].allocationCategoryWeights[].weight` | float×178 |
| `[].closingPrice` | float×36, NoneType×6 |
| `[].closingPriceUpdatedAt` | NoneType×38, str×4 |
| `[].costBasis` | float×33, NoneType×9 |
| `[].holdingClassification` | NoneType×42 |
| `[].id` | str×42 |
| `[].isManual` | bool×42 |
| `[].name` | str×42 |
| `[].quantity` | float×42 |
| `[].security` | dict×42 |
| `[].security.__typename` | str×42 |
| `[].security.assetClass` | str×42 |
| `[].security.closingPrice` | float×42 |
| `[].security.closingPriceUpdatedAt` | str×40, NoneType×2 |
| `[].security.currentPrice` | float×39, NoneType×3 |
| `[].security.currentPriceUpdatedAt` | str×39, NoneType×3 |
| `[].security.id` | str×42 |
| `[].security.name` | str×42 |
| `[].security.oneDayChangeDollars` | float×38, NoneType×4 |
| `[].security.oneDayChangePercent` | float×38, NoneType×4 |
| `[].security.ticker` | str×40, NoneType×2 |
| `[].security.type` | str×42 |
| `[].security.typeDisplay` | str×42 |
| `[].securityClassification` | NoneType×42 |
| `[].taxLots` | list×42 |
| `[].ticker` | str×40, NoneType×2 |
| `[].type` | str×42 |
| `[].typeDisplay` | str×42 |
| `[].userCostBasis` | NoneType×42 |
| `[].value` | float×42 |

## import/merchants.json  (top-level list, 808 entries)

| key path | types seen |
|---|---|
| `[]` | dict×200 |
| `[].canBeDeleted` | bool×200 |
| `[].createdAt` | str×200 |
| `[].defaultCategory` | NoneType×200 |
| `[].defaultCategoryApplicationMode` | str×200 |
| `[].hasActiveRecurringStreams` | bool×200 |
| `[].id` | str×200 |
| `[].logoUrl` | str×103, NoneType×97 |
| `[].name` | str×200 |
| `[].recurrenceIgnoredAt` | NoneType×200 |
| `[].recurringTransactionStream` | NoneType×181, dict×19 |
| `[].recurringTransactionStream.amount` | float×19 |
| `[].recurringTransactionStream.baseDate` | str×19 |
| `[].recurringTransactionStream.frequency` | str×19 |
| `[].recurringTransactionStream.id` | str×19 |
| `[].recurringTransactionStream.isActive` | bool×19 |
| `[].ruleCount` | int×200 |
| `[].transactionCount` | int×200 |

## import/net_worth_daily.json  (top-level list, 392 entries)

| key path | types seen |
|---|---|
| `[]` | dict×200 |
| `[].__typename` | str×200 |
| `[].balance` | float×200 |
| `[].date` | str×200 |

## import/portfolio_performance.json  (top-level list, 15024 entries)

| key path | types seen |
|---|---|
| `[]` | dict×200 |
| `[].account_id` | str×200 |
| `[].date` | str×200 |
| `[].returnPercent` | float×200 |

## import/provenance.json  (top-level dict, 23 entries)

| key path | types seen |
|---|---|
| `accounts` | list×1 |
| `accounts[]` | str×3 |
| `aggregate_holdings` | list×1 |
| `aggregate_holdings[]` | str×2 |
| `attachments` | list×1 |
| `attachments[]` | str×1 |
| `balance_history` | list×1 |
| `balance_history[]` | str×1 |
| `budget_months` | list×1 |
| `budget_months[]` | str×1 |
| `budget_totals` | list×1 |
| `budget_totals[]` | str×1 |
| `categories` | list×1 |
| `categories[]` | str×1 |
| `category_groups` | list×1 |
| `category_groups[]` | str×2 |
| `credit_scores` | list×1 |
| `credit_scores[]` | str×1 |
| `equity_grants` | list×1 |
| `equity_grants[]` | str×1 |
| `goals` | list×1 |
| `goals[]` | str×2 |
| `holdings` | list×1 |
| `holdings[]` | str×2 |
| `merchants` | list×1 |
| `merchants[]` | str×2 |
| `net_worth_daily` | list×1 |
| `net_worth_daily[]` | str×1 |
| `portfolio_performance` | list×1 |
| `portfolio_performance[]` | str×1 |
| `recurring_streams` | list×1 |
| `recurring_streams[]` | str×1 |
| `rules` | list×1 |
| `rules[]` | str×2 |
| `settings_documents` | list×1 |
| `settings_documents[]` | str×1 |
| `tags` | list×1 |
| `tags[]` | str×1 |
| `tax_lots` | list×1 |
| `tax_lots[]` | str×1 |
| `transaction_activity` | list×1 |
| `transaction_activity[]` | str×1 |
| `transaction_tags` | list×1 |
| `transaction_tags[]` | str×1 |
| `transactions` | list×1 |
| `transactions[]` | str×2 |

## import/recurring_streams.json  (top-level list, 24 entries)

| key path | types seen |
|---|---|
| `[]` | dict×24 |
| `[].amount` | float×24 |
| `[].baseDate` | str×24 |
| `[].dayOfTheMonth` | NoneType×24 |
| `[].frequency` | str×24 |
| `[].id` | str×24 |
| `[].isActive` | bool×24 |
| `[].isApproximate` | bool×24 |
| `[].logoUrl` | str×19, NoneType×5 |
| `[].merchant` | dict×24 |
| `[].merchant.id` | str×24 |
| `[].merchant.name` | str×24 |
| `[].name` | str×24 |
| `[].recurringType` | str×24 |
| `[].reviewStatus` | str×24 |

## import/rules.json  (top-level list, 22 entries)

| key path | types seen |
|---|---|
| `[]` | dict×22 |
| `[].__typename` | str×22 |
| `[].accountIds` | NoneType×22 |
| `[].accounts` | list×22 |
| `[].actionSetBusinessEntity` | NoneType×22 |
| `[].actionSetBusinessEntityIsUnassigned` | bool×22 |
| `[].actionSetOwner` | NoneType×22 |
| `[].actionSetOwnerIsJoint` | bool×22 |
| `[].addTagsAction` | NoneType×18, list×4 |
| `[].addTagsAction[]` | dict×4 |
| `[].addTagsAction[].__typename` | str×4 |
| `[].addTagsAction[].color` | str×4 |
| `[].addTagsAction[].id` | str×4 |
| `[].addTagsAction[].name` | str×4 |
| `[].amountCriteria` | NoneType×18, dict×4 |
| `[].amountCriteria.__typename` | str×4 |
| `[].amountCriteria.isExpense` | bool×4 |
| `[].amountCriteria.operator` | str×4 |
| `[].amountCriteria.value` | float×4 |
| `[].amountCriteria.valueRange` | NoneType×4 |
| `[].categories` | list×22 |
| `[].categories[]` | dict×1 |
| `[].categories[].__typename` | str×1 |
| `[].categories[].icon` | str×1 |
| `[].categories[].id` | str×1 |
| `[].categories[].name` | str×1 |
| `[].categoryIds` | NoneType×21, list×1 |
| `[].categoryIds[]` | str×1 |
| `[].criteriaBusinessEntities` | NoneType×22 |
| `[].criteriaBusinessEntityIds` | NoneType×22 |
| `[].criteriaBusinessEntityIsUnassigned` | bool×22 |
| `[].criteriaOwnerIsJoint` | bool×22 |
| `[].criteriaOwnerUserIds` | NoneType×22 |
| `[].criteriaOwnerUsers` | NoneType×22 |
| `[].id` | str×22 |
| `[].lastAppliedAt` | str×12, NoneType×10 |
| `[].linkGoalAction` | NoneType×22 |
| `[].linkSavingsGoalAction` | NoneType×22 |
| `[].merchantCriteria` | list×21, NoneType×1 |
| `[].merchantCriteriaUseOriginalStatement` | bool×22 |
| `[].merchantCriteria[]` | dict×21 |
| `[].merchantCriteria[].operator` | str×21 |
| `[].merchantCriteria[].value` | str×21 |
| `[].merchantNameCriteria` | NoneType×21, list×1 |
| `[].merchantNameCriteria[]` | dict×1 |
| `[].merchantNameCriteria[].operator` | str×1 |
| `[].merchantNameCriteria[].value` | str×1 |
| `[].needsReviewByUserAction` | NoneType×22 |
| `[].order` | int×22 |
| `[].originalStatementCriteria` | NoneType×22 |
| `[].recentApplicationCount` | int×22 |
| `[].reviewStatusAction` | NoneType×22 |
| `[].sendNotificationAction` | bool×22 |
| `[].setCategoryAction` | dict×22 |
| `[].setCategoryAction.__typename` | str×22 |
| `[].setCategoryAction.icon` | str×22 |
| `[].setCategoryAction.id` | str×22 |
| `[].setCategoryAction.name` | str×22 |
| `[].setHideFromReportsAction` | bool×22 |
| `[].setLinkToPaydownBudgetAction` | bool×22 |
| `[].setMerchantAction` | NoneType×22 |
| `[].splitTransactionsAction` | NoneType×22 |
| `[].unassignNeedsReviewByUserAction` | bool×22 |

## import/settings_documents.json  (top-level list, 18 entries)

| key path | types seen |
|---|---|
| `[]` | dict×18 |
| `[].data` | dict×18 |
| `[].data.budgetApplyToFutureMonthsDefault` | NoneType×2 |
| `[].data.budgetSystem` | str×2 |
| `[].data.businessEntities` | list×1 |
| `[].data.creditReportLiabilityAccounts` | list×1 |
| `[].data.debtAccounts` | list×1 |
| `[].data.debtAccounts[]` | dict×4 |
| `[].data.debtAccounts[].apr` | NoneType×4 |
| `[].data.debtAccounts[].displayBalance` | float×4 |
| `[].data.debtAccounts[].displayLastUpdatedAt` | str×4 |
| `[].data.debtAccounts[].displayName` | str×4 |
| `[].data.debtAccounts[].excludeFromDebtPaydown` | bool×4 |
| `[].data.debtAccounts[].icon` | str×4 |
| `[].data.debtAccounts[].id` | str×4 |
| `[].data.debtAccounts[].includeInNetWorth` | bool×4 |
| `[].data.debtAccounts[].interestRate` | NoneType×4 |
| `[].data.debtAccounts[].isHidden` | bool×4 |
| `[].data.debtAccounts[].logoUrl` | str×4 |
| `[].data.debtAccounts[].minimumPayment` | NoneType×3, float×1 |
| `[].data.debtAccounts[].plannedPayment` | NoneType×4 |
| `[].data.debtAccounts[].subtype` | dict×4 |
| `[].data.debtAccounts[].subtype.display` | str×4 |
| `[].data.debtAccounts[].subtype.name` | str×4 |
| `[].data.debtAccounts[].type` | dict×4 |
| `[].data.debtAccounts[].type.display` | str×4 |
| `[].data.debtAccounts[].type.name` | str×4 |
| `[].data.flexExpenseRolloverPeriod` | NoneType×1 |
| `[].data.householdAccessGrants` | list×1 |
| `[].data.householdInvites` | list×1 |
| `[].data.householdPreferences` | dict×2 |
| `[].data.householdPreferences.accountGroupOrder` | list×1 |
| `[].data.householdPreferences.accountGroupOrder[]` | str×3 |
| `[].data.householdPreferences.accountSortMode` | str×1 |
| `[].data.householdPreferences.aggDataSharingEnabled` | bool×1 |
| `[].data.householdPreferences.aiAssistantEnabled` | bool×1 |
| `[].data.householdPreferences.aiModelTrainingOnUserDataEnabled` | bool×1 |
| `[].data.householdPreferences.assistantEngineExperimentArm` | NoneType×1 |
| `[].data.householdPreferences.budgetApplyToFutureMonthsDefault` | NoneType×1 |
| `[].data.householdPreferences.collaborationToolsEnabled` | bool×1 |
| `[].data.householdPreferences.continuousFinancialMonitoringEnabled` | bool×1 |
| `[].data.householdPreferences.defaultCategoriesExperimentEnabled` | bool×1 |
| `[].data.householdPreferences.disabledInsightTopics` | list×1 |
| `[].data.householdPreferences.eligibleForFinancialInsights` | bool×1 |
| `[].data.householdPreferences.excludeBusinessFromBudget` | bool×1 |
| `[].data.householdPreferences.forecastMonteCarloExperimentEnabled` | bool×1 |
| `[].data.householdPreferences.hiddenTransactionsBetaEnabled` | bool×1 |
| `[].data.householdPreferences.id` | str×2 |
| `[].data.householdPreferences.investmentTransactionsEnabled` | bool×1 |
| `[].data.householdPreferences.llmEnrichmentEnabled` | bool×1 |
| `[].data.householdPreferences.newTransactionsNeedReview` | bool×1 |
| `[].data.householdPreferences.pendingTransactionsCanBeEdited` | bool×1 |
| `[].data.householdPreferences.sunsetCashFlowExperimentArm` | NoneType×1 |
| `[].data.householdPreferences.uncategorizedTransactionsNeedReview` | bool×1 |
| `[].data.me` | dict×2 |
| `[].data.me.activeSupportAccountAccessGrant` | NoneType×1 |
| `[].data.me.attributionData` | dict×1 |
| `[].data.me.attributionData.onboardingQuizCompleted` | bool×1 |
| `[].data.me.attributionData.runwayerOnboardId` | NoneType×1 |
| `[].data.me.avatarColor` | NoneType×1 |
| `[].data.me.birthday` | NoneType×1 |
| `[].data.me.createdAt` | str×1 |
| `[].data.me.displayName` | str×1 |
| `[].data.me.email` | str×1 |
| `[].data.me.externalAuthProviderNames` | list×1 |
| `[].data.me.externalAuthProviderNames[]` | str×1 |
| `[].data.me.hasMfaOn` | bool×1 |
| `[].data.me.hasPassword` | bool×1 |
| `[].data.me.householdRole` | str×2 |
| `[].data.me.id` | str×2 |
| `[].data.me.isSuperuser` | bool×1 |
| `[].data.me.name` | str×1 |
| `[].data.me.onboardingTemplate` | NoneType×1 |
| `[].data.me.pendingEmailUpdateVerification` | NoneType×1 |
| `[].data.me.profile` | dict×1 |
| `[].data.me.profile.collaboratesOnFinancesDetailed` | str×1 |
| `[].data.me.profile.dismissedTransactionsListUpdatesTourAt` | NoneType×1 |
| `[].data.me.profile.hasDismissedWhatsNewAt` | str×1 |
| `[].data.me.profile.hasSeenCategoriesManagementTour` | bool×1 |
| `[].data.me.profile.id` | str×1 |
| `[].data.me.profile.mobileUiThemePreference` | NoneType×1 |
| `[].data.me.profile.userReportedAttributionChannels` | list×1 |
| `[].data.me.profile.userReportedAttributionChannels[]` | str×1 |
| `[].data.me.profile.viewedMarkAsReviewedUpdatesCalloutAt` | str×1 |
| `[].data.me.profile.webUiThemePreference` | NoneType×1 |
| `[].data.me.profilePicture` | NoneType×1 |
| `[].data.me.profilePictureUrl` | str×1 |
| `[].data.me.timezone` | str×1 |
| `[].data.migratedToSavingsGoals` | bool×1 |
| `[].data.myHousehold` | dict×3 |
| `[].data.myHousehold.address` | str×1 |
| `[].data.myHousehold.city` | str×1 |
| `[].data.myHousehold.country` | str×1 |
| `[].data.myHousehold.id` | str×3 |
| `[].data.myHousehold.name` | str×1 |
| `[].data.myHousehold.preferences` | dict×1 |
| `[].data.myHousehold.preferences.dashboardConfig` | dict×1 |
| `[].data.myHousehold.preferences.dashboardConfig.mobile` | dict×1 |
| `[].data.myHousehold.preferences.dashboardConfig.web` | dict×1 |
| `[].data.myHousehold.preferences.dashboardConfigCustomizedAt` | NoneType×1 |
| `[].data.myHousehold.state` | str×1 |
| `[].data.myHousehold.users` | list×1 |
| `[].data.myHousehold.users[]` | dict×1 |
| `[].data.myHousehold.users[].displayName` | str×1 |
| `[].data.myHousehold.users[].email` | str×1 |
| `[].data.myHousehold.users[].financialProfile` | dict×1 |
| `[].data.myHousehold.users[].hasMfaOn` | bool×1 |
| `[].data.myHousehold.users[].hasVerifiedEmail` | bool×1 |
| `[].data.myHousehold.users[].householdRole` | str×1 |
| `[].data.myHousehold.users[].id` | str×1 |
| `[].data.myHousehold.users[].name` | str×1 |
| `[].data.myHousehold.users[].profilePictureUrl` | str×1 |
| `[].data.myHousehold.zipCode` | str×1 |
| `[].data.notificationPreferences` | list×1 |
| `[].data.notificationPreferences[]` | dict×21 |
| `[].data.notificationPreferences[].EMAIL` | bool×21 |
| `[].data.notificationPreferences[].PUSH` | bool×21 |
| `[].data.notificationPreferences[].additionalPreferences` | NoneType×21 |
| `[].data.notificationPreferences[].additionalPreferencesMeta` | dict×21 |
| `[].data.notificationPreferences[].additionalPreferencesMeta.minimum_amount` | dict×2 |
| `[].data.notificationPreferences[].description` | str×21 |
| `[].data.notificationPreferences[].emailEnabled` | bool×19, NoneType×2 |
| `[].data.notificationPreferences[].group` | str×21 |
| `[].data.notificationPreferences[].id` | str×21 |
| `[].data.notificationPreferences[].inAppEnabled` | bool×19, NoneType×2 |
| `[].data.notificationPreferences[].pushEnabled` | bool×19, NoneType×2 |
| `[].data.notificationPreferences[].title` | str×21 |
| `[].data.notificationPreferences[].type` | str×21 |
| `[].data.paychecks` | list×1 |
| `[].data.recurrenceGroupsForPeriod` | list×1 |
| `[].data.reportConfigurations` | list×1 |
| `[].data.retailExtensionSettings` | dict×1 |
| `[].data.retailExtensionSettings.id` | str×1 |
| `[].data.retailExtensionSettings.retailVendorSettings` | list×1 |
| `[].data.retailExtensionSettings.retailVendorSettings[]` | dict×4 |
| `[].data.retailExtensionSettings.retailVendorSettings[].id` | str×4 |
| `[].data.retailExtensionSettings.retailVendorSettings[].merchant` | NoneType×2, dict×2 |
| `[].data.retailExtensionSettings.retailVendorSettings[].shouldCategorizeAndSplitTransactions` | bool×4 |
| `[].data.retailExtensionSettings.retailVendorSettings[].shouldUpdateTransactionsNotes` | bool×4 |
| `[].data.retailExtensionSettings.retailVendorSettings[].vendor` | str×4 |
| `[].data.savingsGoals` | list×1 |
| `[].data.spinwheelUser` | dict×1 |
| `[].data.spinwheelUser.id` | str×1 |
| `[].data.spinwheelUser.isBillSyncTrackingEnabled` | bool×1 |
| `[].data.spinwheelUser.onboardingErrorMessage` | NoneType×1 |
| `[].data.spinwheelUser.onboardingStatus` | str×1 |
| `[].data.spinwheelUser.user` | dict×1 |
| `[].data.spinwheelUser.user.displayName` | str×1 |
| `[].data.spinwheelUser.user.id` | str×1 |
| `[].data.spinwheelUser.user.name` | str×1 |
| `[].data.userProfile` | dict×1 |
| `[].data.userProfile.id` | str×1 |
| `[].data.userProfile.transactionListDisplayPreferences` | dict×1 |
| `[].data.userProfile.transactionListDisplayPreferences.mobile` | list×1 |
| `[].data.userProfile.transactionListDisplayPreferences.mobile[]` | dict×4 |
| `[].data.userProfile.transactionListDisplayPreferences.web` | list×1 |
| `[].data.userProfile.transactionListDisplayPreferences.web[]` | dict×4 |
| `[].name` | str×18 |

## import/tags.json  (top-level list, 7 entries)

| key path | types seen |
|---|---|
| `[]` | dict×7 |
| `[].color` | str×7 |
| `[].id` | str×7 |
| `[].name` | str×7 |
| `[].order` | int×7 |
| `[].transactionCount` | int×7 |

## import/tax_lots.json  (top-level list, 0 entries)

| key path | types seen |
|---|---|

## import/transaction_activity.json  (top-level list, 3844 entries)

| key path | types seen |
|---|---|
| `[]` | dict×200 |
| `[].actor` | dict×200 |
| `[].actor.dataProvider` | str×169 |
| `[].actor.id` | NoneType×200 |
| `[].actor.name` | NoneType×200 |
| `[].actor.type` | str×200 |
| `[].after` | dict×10 |
| `[].after.icon` | NoneType×10 |
| `[].after.label` | str×10 |
| `[].before` | dict×10 |
| `[].before.icon` | NoneType×10 |
| `[].before.label` | str×10 |
| `[].event_index` | int×200 |
| `[].id` | str×200 |
| `[].kind` | str×200 |
| `[].occurredAt` | str×200 |
| `[].subtype` | str×200 |
| `[].transaction_id` | str×200 |

## import/transaction_tags.json  (top-level list, 51 entries)

| key path | types seen |
|---|---|
| `[]` | dict×51 |
| `[].tag_id` | str×51 |
| `[].transaction_id` | str×51 |

## import/transactions.json  (top-level list, 3353 entries)

| key path | types seen |
|---|---|
| `[]` | dict×200 |
| `[].__typename` | str×200 |
| `[].account` | dict×200 |
| `[].account.businessEntity` | NoneType×200 |
| `[].account.displayName` | str×200 |
| `[].account.hideInBudget` | bool×200 |
| `[].account.hideTransactionsFromReports` | bool×200 |
| `[].account.icon` | str×200 |
| `[].account.id` | str×200 |
| `[].account.isLiability` | bool×200 |
| `[].account.linkedGoal` | NoneType×200 |
| `[].account.logoUrl` | str×200 |
| `[].account.ownedByUser` | NoneType×200 |
| `[].account.type` | dict×200 |
| `[].account.type.display` | str×200 |
| `[].account.type.name` | str×200 |
| `[].activityLog` | list×200 |
| `[].activityLog[]` | dict×300 |
| `[].activityLog[].actor` | dict×300 |
| `[].activityLog[].actor.dataProvider` | str×193 |
| `[].activityLog[].actor.id` | NoneType×300 |
| `[].activityLog[].actor.name` | NoneType×300 |
| `[].activityLog[].actor.type` | str×300 |
| `[].activityLog[].after` | dict×11 |
| `[].activityLog[].after.icon` | NoneType×11 |
| `[].activityLog[].after.label` | str×11 |
| `[].activityLog[].before` | dict×11 |
| `[].activityLog[].before.icon` | NoneType×11 |
| `[].activityLog[].before.label` | str×11 |
| `[].activityLog[].id` | str×300 |
| `[].activityLog[].kind` | str×300 |
| `[].activityLog[].occurredAt` | str×300 |
| `[].activityLog[].subtype` | str×300 |
| `[].amount` | float×200 |
| `[].attachments` | list×200 |
| `[].businessEntity` | NoneType×200 |
| `[].businessEntityOverriddenAt` | NoneType×200 |
| `[].category` | dict×200 |
| `[].category.group` | dict×200 |
| `[].category.group.id` | str×200 |
| `[].category.group.name` | str×200 |
| `[].category.group.type` | str×200 |
| `[].category.icon` | str×200 |
| `[].category.id` | str×200 |
| `[].category.name` | str×200 |
| `[].category.systemCategory` | str×194, NoneType×6 |
| `[].createdAt` | str×200 |
| `[].dataProviderDescription` | str×200 |
| `[].date` | str×200 |
| `[].deletedAt` | NoneType×200 |
| `[].deletedByType` | NoneType×200 |
| `[].externalId` | str×200 |
| `[].goal` | NoneType×200 |
| `[].hasSplitTransactions` | bool×200 |
| `[].hiddenByAccount` | bool×200 |
| `[].hideFromReports` | bool×200 |
| `[].id` | str×200 |
| `[].isLinkedToPaydownBudget` | bool×200 |
| `[].isManual` | bool×200 |
| `[].isRecurring` | bool×200 |
| `[].isSplitTransaction` | bool×200 |
| `[].linkedRetailTransactionId` | NoneType×200 |
| `[].merchant` | dict×200 |
| `[].merchant.defaultCategory` | NoneType×200 |
| `[].merchant.defaultCategoryApplicationMode` | str×200 |
| `[].merchant.hasActiveRecurringStreams` | bool×200 |
| `[].merchant.id` | str×200 |
| `[].merchant.logoUrl` | str×116, NoneType×84 |
| `[].merchant.name` | str×200 |
| `[].merchant.recurringTransactionStream` | NoneType×172, dict×28 |
| `[].merchant.recurringTransactionStream.frequency` | str×28 |
| `[].merchant.recurringTransactionStream.id` | str×28 |
| `[].merchant.recurringTransactionStream.isActive` | bool×28 |
| `[].merchant.showDefaultCategoryPrompt` | bool×200 |
| `[].merchant.transactionCount` | int×200 |
| `[].needsReview` | bool×200 |
| `[].needsReviewByUser` | NoneType×200 |
| `[].notes` | NoneType×200 |
| `[].originalDate` | str×200 |
| `[].originalTransaction` | NoneType×200 |
| `[].ownedByUser` | NoneType×200 |
| `[].ownershipOverriddenAt` | NoneType×200 |
| `[].pending` | bool×200 |
| `[].plaidName` | str×200 |
| `[].reviewStatus` | NoneType×200 |
| `[].reviewedAt` | NoneType×200 |
| `[].reviewedByUser` | NoneType×200 |
| `[].savingsGoalEvent` | NoneType×200 |
| `[].splitTransactions` | list×200 |
| `[].tags` | list×200 |
| `[].updatedAt` | str×200 |
| `[].updatedByRetailSync` | bool×200 |

# Enumerations observed (values that drive mapping logic — not personal data)

## accounts: (type.name, subtype.name) → count
```
('credit', 'credit_card'): 5
('brokerage', 'brokerage'): 5
('brokerage', 'st_401k'): 3
('brokerage', 'cryptocurrency'): 3
('depository', 'checking'): 2
('depository', 'savings'): 2
('brokerage', 'ira'): 2
('brokerage', 'roth'): 1
('brokerage', 'health_savings_account'): 1
('brokerage', 'pension'): 1
```
## accounts: credential.dataProvider → count
```
FINICITY: 13
PLAID: 11
COINBASE: 1
```
## accounts: flags
```
isManual: {False: 25}
isHidden: {False: 24, True: 1}
deactivatedAt: {'NoneType': 24, '2026-03-04': 1}
includeInNetWorth: {True: 24, False: 1}
includeBalanceInNetWorth: {True: 23, False: 2}
hideFromList: {False: 25}
hideTransactionsFromReports: {False: 25}
isAsset: {True: 20, False: 5}
invertSyncedBalance: {False: 25}
canInvertBalance: {True: 24, False: 1}
useAvailableBalance: {'NoneType': 24, False: 1}
```
## category_groups: type → count
```
expense: 13
income: 1
transfer: 1
```
## categories: systemCategory values
```
None: 3
advertising_promotion: 1
auto_payment: 1
charity: 1
child_care: 1
garbage: 1
groceries: 1
loan_repayment: 1
medical: 1
mortgage: 1
paychecks: 1
shopping: 1
student_loans: 1
transfer: 1
travel_vacation: 1
uncategorized: 1
business_utilities_communication: 1
check: 1
child_activities: 1
clothing: 1
credit_card_payment: 1
dentist: 1
education: 1
entertainment_recreation: 1
financial_legal_services: 1
gifts: 1
interest: 1
public_transit: 1
rent: 1
restaurants_bars: 1
water: 1
balance_adjustments: 1
business_income: 1
coffee_shops: 1
employee_wages_contract_labor: 1
financial_fees: 1
fitness: 1
furniture_housewares: 1
gas: 1
gas_electric: 1
home_improvement: 1
miscellaneous: 1
personal: 1
auto_maintenance: 1
business_travel_meals: 1
cash_atm: 1
electronics: 1
internet_cable: 1
other_income: 1
pets: 1
business_auto_expenses: 1
fun_money: 1
insurance: 1
parking_tolls: 1
phone: 1
business_insurance: 1
taxes: 1
taxi_ride_shares: 1
office_supplies_expenses: 1
office_rent: 1
postage_shipping: 1
```
## transactions: top-level flags
```
pending: {'False': 3350, 'True': 3}
needsReview: {'False': 3348, 'True': 5}
reviewStatus: {'None': 3326, 'reviewed': 22, 'needs_review': 5}
isSplitTransaction: {'False': 3353}
hideFromReports: {'False': 3344, 'True': 9}
isRecurring: {'False': 3353}
amount sign convention: negative = outflow/expense, positive = inflow (verify: expense-category txns are negative) -> {'neg': 2865, 'pos': 488}
```
## rules: criteria/action keys present (non-null) → count
```
id: 22
setCategoryAction: 22
__typename: 22
merchantCriteria: 21
order: 21
lastAppliedAt: 12
amountCriteria: 4
addTagsAction: 4
recentApplicationCount: 2
merchantCriteriaUseOriginalStatement: 1
categoryIds: 1
categories: 1
merchantNameCriteria: 1
```
## holdings: security.type / typeDisplay → count
```
('equity', 'Stock'): 15
('etf', 'ETF'): 11
('cryptocurrency', 'Cryptocurrency'): 7
('cash', 'Cash'): 6
('other', 'Other'): 2
('mutual_fund', 'Mutual Fund'): 1
```
