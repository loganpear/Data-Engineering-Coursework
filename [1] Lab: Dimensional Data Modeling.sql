select * from player_seasons;

create type scoring_class as enum ('star', 'good', 'average', 'bad');
create type season_stats as (
                            season integer,
                            gp integer,
                            pts real,
                            reb real,
                            ast real

                            );

DROP TABLE IF EXISTS players;

-- Step 2: Create the new table with the updated schema
CREATE TABLE players (
    player_name text,
    height text,
    college text,
    country text, -- ensure correct column name (was "county" instead of "country"?)
    draft_year text,
    draft_round text,
    draft_number text,
    season_stats season_stats[], -- custom type for season stats array
    scoring_class scoring_class,
    years_since_last_season integer,
    current_season integer,
    PRIMARY KEY (player_name, current_season)
);

select * from players;

insert into players
with yesterday as (
    select * from players
    where current_season = 2000
),
    today as (
        select * from player_seasons
        where season = 2001
    )
select
    coalesce(t.player_name, y.player_name) as playername,
    coalesce(t.height, y.height) as height,
    coalesce(t.college, y.college) as college,
    coalesce(t.country, y.country) as country,
    coalesce(t.draft_year, y.draft_year) as draft_year,
    coalesce(t.draft_round, y.draft_round) as draft_round,
    coalesce(t.draft_number, y.draft_number) as draft_number,
    case when y.season_stats is null  -- if its null we create the initial array with one value
        then array[row(
            t.season,
            t.gp,
            t.pts,
            t.reb,
            t.ast
            )::season_stats]  -- the :: casts the array as type season_stats
    when t.season is not null  -- if today i not null then we create the new value
        then y.season_stats || array[row( -- || means concatenate
            t.season,
            t.gp,
            t.pts,
            t.reb,
            t.ast
            )::season_stats]
    else y.season_stats  -- 3rd condition: we carry the players history forward. Ex: retired player that doesn't have any new seasons
    end as season_stats,

    case
        when t.season is not null then
            case when t.pts > 20 then 'star'
                when t.pts > 15 then 'good'
                when t.pts > 10 then 'average'
                else 'bad'
            end::scoring_class
        else y.scoring_class
    end as scoring_class,

    case when t.season is not null then 0
        else y.years_since_last_season + 1
    end as years_since_last_season,

    coalesce(t.season, y.current_season + 1) as current_season
    -- the coalesce above works functionally as the case statement below
    /*case when t.season is not null
        then t.season
        else y.current_season + 1
    end*/

from today t full outer join yesterday y
    on t.player_name = y.player_name;

-- Analysis of how much each player has improved since their debut year
-- this is a very fast query since there's no group by
select
    player_name,
    (season_stats[cardinality(season_stats)]::season_stats).pts /
    case when (season_stats[1]::season_stats).pts = 0 then 1 else (season_stats[1]::season_stats).pts end
from players
where current_season = 2001
and scoring_class = 'star'
order by 2 desc;

with unnested as (select player_name,
                         unnest(season_stats)::season_stats as season_stats
                  from players
                  where current_season = 2001
                    and player_name = 'Michael Jordan')
select player_name, (season_stats::season_stats).*  -- unpacks each item in the array into columns
from unnested;
