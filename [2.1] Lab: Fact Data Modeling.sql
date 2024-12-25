-- Fact Data: Lab 1
-- This lab builds a fact table for game details and analyzes player participation patterns

select * from game_details ;

-- Query to test if there are duplicates
select
    game_id,
    team_id,
    player_id,
    count(1)

from game_details
group by 1, 2, 3
having count(1) > 1;  -- There are :(


-- Creating DDL
drop table if exists fct_game_details;

create table fct_game_details(
    dim_game_date date,
    dim_season integer,
    dim_team_id integer,
    dim_player_id integer,
    dim_player_name text,
    dim_start_position text,
    dim_is_playing_at_home boolean,
    dim_did_not_play boolean,
    dim_did_not_dress boolean,
    dim_not_with_team boolean,
    m_minutes real,  -- the m at the beginning means measure
    m_fgm integer,
    m_fga integer,
    m_fg3m integer,
    m_fg3a integer,
    m_ftm integer,
    m_fta integer,
    m_oreb integer,
    m_dreb integer,
    m_reb integer,
    m_ast integer,
    m_stl integer,
    m_blk integer,
    m_turnovers integer,
    m_pf integer,
    m_pts real,
    m_plus_minus integer,
    primary key (dim_game_date, dim_player_id, dim_team_id)
);


insert into fct_game_details

    with deduped as ( -- Deduplicate data
        select
            g.game_date_est,
            g.season,
            g.home_team_id,
            gd.*,
            row_number() over(partition by gd.game_id, team_id, player_id order by g.game_date_est) as row_num
        from game_details gd
            join games g using(game_id)
    )
    select
        game_date_est as dim_game_date,
        season as dim_season,
        team_id as dim_team_id,
        player_id as dim_player_id,
        player_name as dim_player_name,
        start_position as dim_start_position,
        team_id = home_team_id as dim_is_playing_at_home,  -- Boolean

        coalesce(position('DNP' in comment), 0) > 0 as dim_did_not_play,
        coalesce(position('DND' in comment), 0) > 0 as dim_did_not_dress,
        coalesce(position('NWT' in comment), 0) > 0 as dim_not_with_team,

        -- the analysts are likely gonna want minutes with seconds as decimal so they can easily analyze X stat per minute
        cast(split_part(min, ':', 1) as real)
            + cast(split_part(min, ':', 2) as real) / 60 as m_minutes,

        fgm AS m_fgm,
        fga AS m_fga,
        fg3m AS m_fg3m,
        fg3a AS m_fg3a,
        ftm AS m_ftm,
        fta AS m_fta,
        oreb AS m_oreb,
        dreb AS m_dreb,
        reb AS m_reb,
        ast AS m_ast,
        stl AS m_stl,
        blk AS m_blk,
        "TO" AS m_turnovers,
        pf AS m_pf,
        pts AS m_pts,
        plus_minus AS m_plus_minus

        from deduped
        where row_num = 1;  -- gets rid of duplicates


select * from fct_game_details;


-- Query to find the player that bailed out on the most games
select
    dim_player_name,
    count(dim_player_name) as num_games,
    count(case when dim_not_with_team then 1 end) as most_bails,

    -- Bail percent calculation - NOTE: PostgeSQL performs integer division (// in python) when the numerator and denominator are integers
        count(case when dim_not_with_team then 1 end)::real /
        count(dim_player_name) as bail_pct

from fct_game_details
group by 1
order by 4 desc;
