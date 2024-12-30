-- Lab 3
-- Reduced Fact Table


DROP TABLE IF EXISTS array_metrics;

CREATE TABLE array_metrics (
    user_id NUMERIC,
    month_start DATE,
    metric_name TEXT,
    metric_array REAL[],
    PRIMARY KEY (user_id, month_start, metric_name)
);



insert into array_metrics

WITH daily_aggregate AS (
    SELECT
        user_id,
        DATE(event_time) as date,
        COUNT(user_id) as num_site_hits
    FROM events
    WHERE DATE(event_time) = DATE('2023-01-03')
    AND user_id IS NOT NULL
    GROUP BY user_id, DATE(event_time)
),
    yesterday_array AS (
        SELECT *
        FROM array_metrics
        WHERE month_start = DATE('2023-01-01')
    )

SELECT
    coalesce(da.user_id, ya.user_id) as user_id,
    -- Combines user IDs and aligns dates to the start of the month for merging daily and prior data.
    coalesce(ya.month_start, DATE_TRUNC('month', da.date)) as month,
    'site_hits' as metric_name,
    case
        when ya.metric_array is not null
            then ya.metric_array || array[coalesce(da.num_site_hits, 0)]
        when ya.metric_array is null
            then array_fill(0, array[coalesce(date -  DATE(DATE_TRUNC('month', date)), 0)]) || array[coalesce(da.num_site_hits, 0)]
    end as metric_array

FROM daily_aggregate da
    full outer join yesterday_array ya
        using(user_id)

ON CONFLICT (user_id, month_start, metric_name)
DO
    UPDATE SET metric_array = excluded.metric_array;


select * from array_metrics;


-- Query to make sure everyone's array is filled correctly with 0's where null
select
    cardinality(metric_array),
    count(1)
from array_metrics
group by 1;


-- calculate total site hits for each day 
with agg as (select metric_name,
                    month_start,
                    array [
                        sum(metric_array[1]),
                        sum(metric_array[2]),
                        sum(metric_array[3])
                        ] as summed_array

             from array_metrics
             group by metric_name, month_start)

select
    metric_name,
    month_start + ((index - 1)::text || 'day')::interval as days_from_start,
    elem as value
from agg
    cross join unnest(agg.summed_array)
        with ordinality as a(elem, index)
