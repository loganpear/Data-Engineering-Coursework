-- Lab 2: User Activity Tracking with Bitwise

--This lab tracks user activity over time by backfilling daily activity data storing it in an array,
-- and using bitwise operations to efficiently compute whether users were active daily, weekly, or monthly

select * from events;  -- This table is of every network request


drop table if exists users_cumulated;

create table users_cumulated (
    -- you would use BIGINT not INT bc the user IDs are bigger than 2 billion
    -- but these user IDs are even too big for BIG INT so we're making them texts
    user_id text,
    dates_active DATE[],  -- list of dates in the past where the user was active
    date DATE,  -- current Date
    primary key (user_id, date)
);


-- In the lab they backfill manually, but I asked ChatGPT to write a loop for me to backfill
DO $$
DECLARE
    start_date DATE := DATE '2023-01-01';  -- Start date
    end_date DATE := DATE '2023-01-31';    -- End date
BEGIN
    -- Loop through each date from start_date to end_date
    WHILE start_date <= end_date LOOP

        -- Insert data for the current date
        INSERT INTO users_cumulated
        WITH yesterday AS (
            SELECT *
            FROM users_cumulated
            WHERE date = start_date - INTERVAL '1 day'  -- Previous day
        ),
        today AS (
            SELECT
                (user_id::text) AS user_id,
                DATE(event_time::timestamp) AS date_active
            FROM events
            WHERE DATE(event_time::timestamp) = start_date  -- Current date
                AND user_id IS NOT NULL
            GROUP BY (user_id, DATE(event_time::timestamp))
        )
        SELECT
            COALESCE(t.user_id, y.user_id) AS user_id,
            CASE
                WHEN y.dates_active IS NULL
                    THEN ARRAY[t.date_active]
                WHEN t.date_active IS NULL
                    THEN y.dates_active
                ELSE
                    ARRAY[t.date_active] || y.dates_active
            END AS dates_active,
            COALESCE(t.date_active, y.date + INTERVAL '1 day') AS date
        FROM today t
        FULL OUTER JOIN yesterday y
            USING(user_id);

        -- Move to the next day
        start_date := start_date + INTERVAL '1 day';
    END LOOP;
END $$;


-- Fun fact: at facebook they use 28 days for 1 month casue 28 % 7 = 0 so there's the same num f mondays, tuesdays ect

with users as (
        select *
        from users_cumulated
        where date = date('2023-01-31')
),
series AS (
    SELECT generate_series(
        DATE('2023-01-01'),
        DATE('2023-01-31'),
        INTERVAL '1 day'
    ) AS series_date
),

place_holder_ints as (

    select
        date - date(series_date),
        case
            when dates_active @> array[date(series_date)]
                -- we're using powers of 2 where if they're active today then (date - series_date) = 0
                then cast(pow(2, 32 - (date - (date(series_date)))) as bigint)
            else 0
        end as placeholder_int_value,
        *
    from users cross join series

    -- where user_id = '70132547320211180'
)

select
    user_id,
    sum(placeholder_int_value),

    (sum(placeholder_int_value)
        ::bigint)  -- cast as bigint first
        ::bit(32),  -- cast as bit32 second

    -- Monthly active boolean
    bit_count(
        (sum(placeholder_int_value)
            ::bigint)  -- cast as bigint first
            ::bit(32)  -- cast as bit32 second
        ) > 0 as dim_is_monthly_active,

    -- Weekly active boolean using "bitwise and"
    bit_count(
        ('11111110000000000000000000000000'::bit(32)) &
        ((sum(placeholder_int_value)::BIGINT)::BIT(32))
    ) > 0 as dim_is_weekly_active,

    -- Daily active boolean
    bit_count(
        ('10000000000000000000000000000000'::bit(32)) &
        ((sum(placeholder_int_value)::BIGINT)::BIT(32))
    ) > 0 as dim_is_daily_active

from place_holder_ints
group by user_id;
