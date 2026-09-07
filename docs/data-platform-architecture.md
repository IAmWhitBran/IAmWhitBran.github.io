---
layout: page
title: "Data Platform Architecture"
permalink: /data-platform-architecture
created: 2026/08/30
updated: 2026/09/07
review_by:
status: seedling
---

Medallion architecture, kimball, lambda. etc
notes to follow

## Streaming data
Timestamp when generated and when recieved

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