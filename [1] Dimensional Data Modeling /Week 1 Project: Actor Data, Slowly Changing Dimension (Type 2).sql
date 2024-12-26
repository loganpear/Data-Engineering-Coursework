-- PROJECT ONE: ACTOR FILMS

-- Step 1: Create the actors table with fields to track films, quality_class, and is_active status.
-- Step 2: Write a cumulative query to populate the actors table year-by-year using today and yesterday CTEs.
-- Step 3: Create the actors_history_scd table to track historical changes using Type 2 SCD modeling.
-- Step 4: Write a backfill query to populate the actors_history_scd table with historical data in one query.
-- Step 5: Implement an incremental query to update the actors_history_scd table with new changes over time.


-- View the data set
select * from actor_films limit 20;

-- Step 1: Create types and tables
drop type if exists films;

create type films as (
    film text,
    votes integer,
    rating real,
    filmid text  -- film IDs start with letters ex: tt0082449 so they're TEXT
                  );


drop type quality_class;

create type quality_class as
    enum('star', 'good', 'average', 'bad');


drop table if exists actors;

create table actors (
    actorid text,
    actor text,
    year integer,
    films films[],
    quality_class quality_class,
    is_active boolean,
    primary key (actorid)
);

select * from actors;

select min(year), max(year) from actor_films;  -- 1970 to 2021

-- Step 2: Write a cumulative query to populate the actors table
do $$
declare
    start_year int := 1970;
    end_year int := 2021;
    current_year int;
begin
    -- Loop through each year
    for current_year in start_year..end_year loop

        -- Upsert data for the current year
        insert into actors
        with yesterday as (
            select *
            from actors
            where year = current_year - 1  -- Previous year
        ),
        today as (
            select
                actorid,
                actor,
                year,
                array_agg(row(film, votes, rating, filmid)::films) as films -- Aggregate today's films
            from actor_films
            where year = current_year
            group by actorid, actor, year
        ),
        all_films as (
            select
                coalesce(t.actorid, y.actorid) as actorid,
                coalesce(t.actor, y.actor) as actor,
                coalesce(y.films, array[]::films[]) || coalesce(t.films, array[]::films[]) as films -- Combine films
            from today t
            full outer join yesterday y
                on t.actorid = y.actorid
        ),
        avg_rating as (
            select
                actorid,
                avg((f).rating) as avg_rating
            from all_films,
                 unnest(films) as f
            group by actorid
        )
        select
            coalesce(t.actorid, y.actorid) as actorid,
            coalesce(t.actor, y.actor) as actor,
            current_year as year,

            -- Append or carry forward films
            case
                when y.films is null
                    then t.films
                when t.films is not null
                    then y.films || t.films
                else
                    y.films
            end as films,

            -- Quality class based on updated avg_rating
            case
                when a.avg_rating > 8 then 'star'
                when a.avg_rating > 7 then 'good'
                when a.avg_rating > 6 then 'average'
                else 'bad'
            end::quality_class,

            -- Active status based on whether actor has new films
            case
                when t.films is not null then true
                else false
            end as is_active

        from today t
        full outer join yesterday y
            on t.actorid = y.actorid
        left join avg_rating a
            on coalesce(t.actorid, y.actorid) = a.actorid

        -- Handle duplicates: Insert new or update existing records
        on conflict (actorid)
        do update
            set films = excluded.films,
                quality_class = excluded.quality_class,
                is_active = excluded.is_active,
                year = excluded.year; -- Update the year

    end loop;
end $$;


-- Step 3: Create the actors_history_scd table for SCD Type 2 tracking

drop table if exists actors_history_scd;

create table actors_history_scd (
    actorid text,                          -- Unique identifier for each actor
    quality_class quality_class,           -- Actor's performance classification
    is_active boolean,                      -- Whether the actor is active in the current year
    start_date integer,                     -- Year the record starts being valid
    end_date integer,                       -- Year the record stops being valid
    is_current boolean default true,       -- Flag for the most recent record
    primary key (actorid, start_date)       -- Composite key for uniqueness
);

select * from actors_history_scd;


-- Step 4: Backfill Query for actors_history_scd

insert into actors_history_scd
    select
        actorid,                               -- Actor's unique ID
        quality_class,                         -- Current quality class
        is_active,                             -- Current active status
        min(year) as start_date,               -- Start year for the record
        lead(year, 1, 9999) over (             -- End year for the record
            partition by actorid               -- Partitioned by actor
            order by year                      -- Ordered by year
        ) - 1 as end_date,                      -- Subtract 1 to set the end of the validity period
        case                                   -- Set the current flag for the latest record
            when lead(year, 1) over (
                    partition by actorid
                    order by year
                ) is null then true
            else false
        end as is_current
    from actors
    group by actorid, quality_class, is_active, year
    order by actorid, start_date;


-- Step 5: Incremental Query for SCD Table

-- Insert or update records in actors_history_scd
insert into actors_history_scd
    select
        a.actorid,
        a.quality_class,
        a.is_active,
        -- Set the start date as the current year
        a.year as start_date,
        -- Default end date for new records is 9999 (open-ended)
        9999 as end_date,
        -- Mark the record as current
        true as is_current
    from actors a
    left join actors_history_scd scd
        on a.actorid = scd.actorid
        and scd.is_current = true -- Only compare with current records
    where
        -- Insert new records only if there is a change in quality_class or is_active
        (scd.actorid is null) -- New actor (not in history)
        or (scd.quality_class <> a.quality_class -- Change in quality_class
            or scd.is_active <> a.is_active); -- Change in active status


-- End the validity of old records when changes are detected
update actors_history_scd
    set end_date = a.year - 1, -- Set the end date to one year before the new record starts
        is_current = false -- Mark the old record as no longer current
    from actors a
    where actors_history_scd.actorid = a.actorid
        and actors_history_scd.is_current = true -- Only update current records
        and (actors_history_scd.quality_class <> a.quality_class -- Detect changes
             or actors_history_scd.is_active <> a.is_active);
