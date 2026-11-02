---
publish: true
created: 2026/08/30
modified: 2026-11-02T16:37
published: 2026-11-02T16:37:45.954Z
updated: 2026-11-02T16:37
review_by:
status: seedling
---

Medallion architecture, kimball, lambda. etc
notes to follow

## Streaming data

Timestamp when generated and when received

### Late arriving data

- Can batch by recieve time if data supports it
- "Allowed lateness" - hold off processing by a small delay to allow for late messages
- Late arriving workflow - batch processing through a separate flow to order messages correctly

## Data testing

Overlaps heavily with alerting for production

- Data quality checks
- Data quantity checks
- Unit testing with synthetic data
- Enforcing schema adherance
- Rejected records processing
