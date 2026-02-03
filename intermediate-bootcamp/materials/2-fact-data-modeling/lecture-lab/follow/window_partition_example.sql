-- PostgreSQL Window Function Example: PARTITION BY
-- This file demonstrates how to use window functions with the PARTITION BY clause
-- to calculate metrics per group (e.g., per user) while still having access to the
-- full result set.

-- Sample table definition (for context)
-- CREATE TABLE events (
--   event_id   SERIAL PRIMARY KEY,
--   user_id    INTEGER NOT NULL,
--   event_type TEXT    NOT NULL,
--   event_ts   TIMESTAMP NOT NULL
-- );

-- 1. Row number per user ordered by event timestamp
SELECT
    event_id,
    user_id,
    event_type,
    event_ts,
    ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY event_ts) AS rn_per_user
FROM events
ORDER BY user_id, event_ts;

-- 2. Cumulative count of events per user
SELECT
    event_id,
    user_id,
    event_type,
    event_ts,
    COUNT(*) OVER (PARTITION BY user_id ORDER BY event_ts
                   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_count
FROM events
ORDER BY user_id, event_ts;

-- 3. Running total of a numeric column (e.g., amount) per user
-- Assuming a column amount exists:
-- SELECT
--   event_id,
--   user_id,
--   amount,
--   SUM(amount) OVER (PARTITION BY user_id ORDER BY event_ts
--                    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total
-- FROM events
-- ORDER BY user_id, event_ts;

-- 4. Percent rank of each event within its user group
SELECT
    event_id,
    user_id,
    event_type,
    event_ts,
    PERCENT_RANK() OVER (PARTITION BY user_id ORDER BY event_ts) AS pct_rank
FROM events
ORDER BY user_id, event_ts;

-- 5. First and last event per user using FIRST_VALUE / LAST_VALUE
SELECT
    event_id,
    user_id,
    event_type,
    event_ts,
    FIRST_VALUE(event_type) OVER (PARTITION BY user_id ORDER BY event_ts
                                 ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS first_event_type,
    LAST_VALUE(event_type) OVER (PARTITION BY user_id ORDER BY event_ts
                                 ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_event_type
FROM events
ORDER BY user_id, event_ts;

-- These examples illustrate how PARTITION BY groups rows for each user while
-- allowing calculations that consider the ordering within each group.
