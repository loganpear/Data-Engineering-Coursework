-- Project 2: Fact Data Modeling

-- Test to see if there are duplicate records
select
    game_id,
    player_id,
    count(1)
from game_details
group by game_id, player_id
having count(1) > 1;


select * from events;  -- see the events table


-- Query 1: Deduplicate game_details

with deduped as (
    select
        *,
        row_number() over (partition by game_id, player_id) as row_num
    from game_details
    )

select * from deduped
where row_num = 1;


-- Query 2: DDL for user_devices_cumulated

drop table if exists  user_devices_cumulated;

CREATE TABLE user_devices_cumulated (
    user_id NUMERIC PRIMARY KEY, -- Unique identifier for each user
    device_activity_datelist JSONB -- Maps browser type to an array of active dates
);


-- Query 3: cumulative query to generate device_activity_datelist from events

WITH activity AS (
    SELECT
        user_id,
        ARRAY_AGG(DISTINCT DATE(event_time) ORDER BY DATE(event_time)) AS active_dates -- Collect distinct dates
    FROM events
    WHERE user_id IS NOT NULL -- Filter out NULL user_id values
    GROUP BY user_id
)

INSERT INTO user_devices_cumulated (user_id, device_activity_datelist)
SELECT
    user_id,
    TO_JSONB(active_dates) -- Cast sorted array to JSONB
FROM activity
ON CONFLICT (user_id) DO UPDATE
SET device_activity_datelist = (
    SELECT TO_JSONB(
        ARRAY(
            SELECT DISTINCT unnest(
                ARRAY(
                    SELECT jsonb_array_elements_text(user_devices_cumulated.device_activity_datelist)::DATE
                ) || ARRAY(
                    SELECT unnest(
                        ARRAY(SELECT DISTINCT DATE(event_time)
                              FROM events
                              WHERE events.user_id = EXCLUDED.user_id AND events.user_id IS NOT NULL)
                    )
                )
            )
            ORDER BY 1 -- Sorting happens here, outside TO_JSONB
        )
    )
);

-- Check that output looks correct
select * from user_devices_cumulated;


-- Query 4: A datelist_int generation query

ALTER TABLE user_devices_cumulated
ADD COLUMN datelist_int BIGINT DEFAULT 0; -- Stores activity as a binary integer


UPDATE user_devices_cumulated AS u
SET datelist_int = (
    SELECT BIT_OR(
        (1 << (DATE_PART('day', active_date::DATE)::INT - 1))::BIGINT -- Set bit based on day
    )
    FROM jsonb_array_elements_text(u.device_activity_datelist) AS t(active_date) -- Process each row
)
WHERE u.device_activity_datelist IS NOT NULL; -- Ensure updates only apply to rows with data


-- Check that output looks correct
select * from user_devices_cumulated;


-- Query 5: A DDL for hosts_cumulated table

DROP TABLE IF EXISTS hosts_cumulated;

CREATE TABLE hosts_cumulated (
    host_name TEXT PRIMARY KEY, -- Descriptive name for hostname
    host_activity_datelist JSONB -- Logs activity dates for each host as an array
);


-- Query 6: Incremental query to generate host_activity_datelist

WITH activity AS (
    SELECT
        host AS host_name, -- Use descriptive name for clarity
        ARRAY_AGG(DISTINCT DATE(event_time) ORDER BY DATE(event_time)) AS active_dates -- Collect distinct dates
    FROM events
    WHERE host IS NOT NULL -- Exclude rows with NULL hosts
    GROUP BY host
)

INSERT INTO hosts_cumulated (host_name, host_activity_datelist)
SELECT
    host_name,
    TO_JSONB(active_dates) -- Convert the sorted array to JSONB format
FROM activity
ON CONFLICT (host_name) DO UPDATE
SET host_activity_datelist = (
    SELECT TO_JSONB(
        ARRAY(
            SELECT DISTINCT unnest(
                ARRAY(
                    SELECT jsonb_array_elements_text(hosts_cumulated.host_activity_datelist)::DATE
                ) || ARRAY(
                    SELECT unnest(
                        ARRAY(SELECT DISTINCT DATE(event_time)
                              FROM events
                              WHERE events.host = EXCLUDED.host_name AND events.host IS NOT NULL)
                    )
                )
            )
            ORDER BY 1 -- Sort dates in ascending order
        )
    )
);

-- Check that output looks correct
select * from hosts_cumulated;


-- Query 7: DDL for Monthly Reduced Fact Table - host_activity_reduced

DROP TABLE IF EXISTS host_activity_reduced;

CREATE TABLE host_activity_reduced (
    month DATE, -- Start of the month (e.g., '2023-01-01')
    host_name TEXT, -- Hostname for the activity
    hit_array INTEGER[], -- Array of total hits per day (1–31)
    unique_visitors_array INTEGER[], -- Array of distinct visitors per day (1–31)
    PRIMARY KEY (month, host_name) -- Unique per host and month
);


-- Query 8: Incremental query that loads host_activity_reduced

WITH daily_activity AS (
    SELECT
        host AS host_name,
        DATE_TRUNC('month', event_time::TIMESTAMP) AS month, -- Explicit cast to TIMESTAMP
        DATE_PART('day', event_time::TIMESTAMP)::INT AS day, -- Explicit cast to TIMESTAMP
        COUNT(1) AS hits, -- Total events (hits) for that day
        COUNT(DISTINCT user_id) AS unique_visitors -- Unique users for that day
    FROM events
    WHERE host IS NOT NULL -- Ignore rows with null hosts
    GROUP BY host, DATE_TRUNC('month', event_time::TIMESTAMP), DATE_PART('day', event_time::TIMESTAMP)
)

INSERT INTO host_activity_reduced (month, host_name, hit_array, unique_visitors_array)
SELECT
    month,
    host_name,
    ARRAY(
        SELECT COALESCE(SUM(hits), 0) -- Fill missing days with 0s
        FROM generate_series(1, 31) AS d(day) -- 1–31 days in a month
        LEFT JOIN daily_activity da
        ON d.day = da.day AND da.host_name = daily_activity.host_name AND da.month = daily_activity.month
        GROUP BY d.day
        ORDER BY d.day
    ) AS hit_array,
    ARRAY(
        SELECT COALESCE(SUM(unique_visitors), 0) -- Fill missing days with 0s
        FROM generate_series(1, 31) AS d(day)
        LEFT JOIN daily_activity da
        ON d.day = da.day AND da.host_name = daily_activity.host_name AND da.month = daily_activity.month
        GROUP BY d.day
        ORDER BY d.day
    ) AS unique_visitors_array
FROM daily_activity
GROUP BY month, host_name
ON CONFLICT (month, host_name) DO UPDATE
SET hit_array = EXCLUDED.hit_array,
    unique_visitors_array = EXCLUDED.unique_visitors_array;
