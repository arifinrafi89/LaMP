# Golden numbers

Copied from LaMP.ai `docs/PLAN.md` section 6 at `e8a4cec`. `tests/engines/test_golden.py` checks every one, as of 2026-10-16.


Farhan designs `seed/green_life.json` so the engines output these. Tests assert them. The frontend, deck, video and docs quote them.

| Quantity | Value |
|---|---|
| Sales, last 30 days | 412,500 |
| Gross margin (setting) | 12% → gross profit 49,500 |
| Overheads, 30 days | 36,000 |
| Net profit, 30 days | 13,500 |
| Stock value / stock days | 210,000 / 17.4 days (on purchases at cost: 363,000 per 30 days) |
| Patient dues / days | 38,000 / 2.8 days |
| Active suppliers | 23 |
| Invoices last 3 months / paid on time | 41 / 38 (all supplier-confirmed in seed) |
| Batches expiring ≤ 60 days | 6 batches, cost value 18,400 |
| Return-eligible value | 9,200 |
| Supplier A order | 60,000, due in 10 days |
| Forecast cash on that day | 41,000 → shortfall 19,000 |
| Slow-mover line | 30 boxes × 600; rate 0.2/day; 90 days to expiry; 30-day buffer → 60 sellable days → 12 sellable; at risk 10,800 |
| Trimmed order / new shortfall | 49,200 / 8,200 |
| Option: supplier extension (20 days) | cost 0, uncertain |
| Option: mobile-wallet loan 8,200 @ 9%, 90 days | 181.97 |
| Option: bank-funded supplier credit 1% on 49,200 | 492.00 |
| Option: bank small-business loan | ineligible (minimum 200,000) |
| Naive: mobile-wallet loan 19,000 @ 9%, 90 days | 421.64 |
| Passport θ lower bound (5th pct of Beta(39, 4)) | 0.826 |
| Default probability (lender model) | 0.030 |
| Score S | 0.507 |
| Advance rate / partner share | 75.2% / 54.4% |
| Shelf-life credit: purpose-blind lender / not financed / financeable | 19,000 / 10,800 / 8,200 |
| Cost disclosure: wallet loan | APR 9% on 8,200 for 90 days; cost of the gap 181.97 = 2.22% of the need |
| Cost disclosure: bank-funded supplier credit | APR 12.2% on 49,200 for 30 days; 492.00 = 6.0% of the need |
| Borrowing ceiling (DBR cap 35% of monthly net cash flow 13,500) | 8,200 loan → 2,793.99/month = 20.7% (allowed); 19,000 → 6,473.88/month = 48.0% (refused) |
| Value ledger total after the demo story | 9,200 + 10,800 + 239.67 = 20,239.67 |
| Statement reconciliation | 11 matched, 1 duplicate (Q-3130, 8,600), 1 unmatched (4,500), 1 missing (T-3134) |
| Fallback deadline if Supplier A doesn't reply | Thu 22 Oct (Fri 23 is the weekly holiday) |
| Demo owner PIN (sandbox) | 2468 |

