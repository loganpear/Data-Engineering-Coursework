-- Lab 3 starts below: Modeling graph data

-- Defines categories for Nodes
create type vertex_type as
    enum('player', 'team', 'game');

drop table if exists vertices;

-- Stores nones in the graph
create table vertices (
    identifier text,
    type vertex_type,
    properties json,
    primary key(identifier, type)
);

drop type edge_type cascade;  -- include cascade at the end cause you cant simply dop the type since other object depend on the pre established edge_type with the error in it.

-- defines relationships (aka edges)
create type edge_type as
    enum('plays_against',
        'shares_team',
        'plays_in', -- a player plays "in" a GAME
        'plays_on' -- a player plays "on" a TEAM
);

drop table if exists edges;

create table edges (
    subject_identifier text,
    subject_type vertex_type,
    object_identifier text,
    object_type vertex_type,
    edge_type edge_type,
    properties json,

    -- The primary kep is essentially everything except for properties
    primary key(subject_identifier,
               subject_type,
               object_identifier,
               object_type,
               edge_type)
);

insert into vertices
    select
        game_id as identifier,
        'game'::vertex_type as type,
        json_build_object(  -- this function builds a dictionary type structure (json)
                -- key TEXT, value
                'pts_home', pts_home,
                'pts_away', pts_away,
                'winning_team', case
                                    when home_team_wins = 1
                                        then home_team_id
                                    else
                                        visitor_team_id end
        ) as properties

    from games;


insert into vertices

    -- aggregated view
    with players_agg as (
        select
            player_id as identifier,
            max(player_name) as player_name,  -- we do max() here just to get one name
            count(1) as number_of_games,
            sum(pts) as total_points,
            array_agg(distinct team_id) as teams

        from game_details
        group by player_id)

    select
        identifier,
        'player'::vertex_type,
        json_build_object(
            'player_name', player_name,
            'number_of_games', number_of_games,
            'total_points', total_points,
            'teams', teams
           )

    from players_agg;


insert into vertices

    -- there was a mistake in creating the teams table, there are three identical records for each unique record
    -- our simple solution is to dedupe with a CTE
    with teams_deduped as (
        select *, row_number() over(partition by team_id) as row_num
        from teams
    )

    select
        team_id as identifier,
        'team':: vertex_type as type,
        json_build_object(
            'abbreviation', abbreviation,
            'nickname', nickname,
            'city', city,
            'year_founded', yearfounded  -- we're adding in an underscore to yearfounded
            )

    from teams_deduped
    where row_num = 1  -- basically there are 3 of each record so we just select the 1st one to work with
;

select              -- TYPE,  COUNT
    type,           -- team,   30
    count(1)        -- player, 1496
from vertices      -- game,   9384
group by 1;


insert into edges

    with deduped as (
        select *, row_number() over(partition by  player_id, game_id) as row_num
        from game_details
    )
    select
        player_id as subject_identifier,
        'player'::vertex_type as subject_type,
        game_id as object_identifier,
        'game'::vertex_type as object_type,
        'plays_in'::edge_type as edge_type,

        json_build_object(
            'start_position', start_position,  -- ex: center, forward
            'pts', pts,
            'team_id', team_id,
            'team_abbreviation', team_abbreviation
        ) as properties

    from deduped
    where row_num = 1;

-- This query finds the player with the highest points scored in a single game
select
    v.properties->>'player_name',  -- the ->> is like indexing the KEY: 'player_name'
    max(cast(e.properties->>'pts' as integer))

from vertices v join edges e
    on e.subject_identifier = v.identifier
    and e.subject_type = v.type

group by 1
order by 2 desc;


insert into edges

    with deduped as (
        select *, row_number() over(partition by  player_id, game_id) as row_num
        from game_details
    ),
    filtered as (
        select *
        from deduped
        where row_num = 1
    ),
    aggregated as (
        -- we want to create an edge where we have plays against between to two players
        -- an edge on either side - self join
        select
            f1.player_id as subject_player_id,
            f2.player_id as object_player_id,

            case
                when f1.team_abbreviation = f2.team_abbreviation -- aka when players are on the same team
                    then 'shares_team'::edge_type
                else -- when players are not on the same team
                    'plays_against'::edge_type
            end as edge_type,

            -- aggregate the names so you just choose one since they could change names throughout time
            max(f1.player_name) as subject_player_name,
            max(f2.player_name) as object_player_name,

            count(1)    as num_games,
            sum(f1.pts) as subject_points,
            sum(f2.pts) as object_points

        from filtered f1
                 join filtered f2
                      on f1.game_id = f2.game_id
                          and f1.player_name <> f2.player_name

        -- the code so far queries for two edges which can be nice when doing analysis,
        -- but to reduce repeated info in data we will make it one-sided with the code below
        where f1.player_id > f2.player_id -- note this is a string comparison but ultimately it just
        -- chooses one records where the first players name is technically > the second so you dont get repeating records (backwards of previos records)

        group by 1, 2, 3
    )
    select
        subject_player_id as subject_identifier,
        'player'::vertex_type as subject_type,
        object_player_id as object_identifier,
        'player'::vertex_type as object_type,
        edge_type as edge_type,
        json_build_object(
            'num_games', num_games,
            'subject_points', subject_points,
            'object_points', object_points
        )
    from aggregated;

select
    v.properties->>'player_name',
    e.object_identifier,
    cast(v.properties->>'number_of_games' as real) /
        case  -- so then instead of dividing by 0 (when it happens) it divides by 1
            when cast(v.properties->>'total_points' as real) = 0
                then 1
            else
                cast(v.properties->>'total_points' as real)
        end as avg_pts_per_game,

    e.properties->>'subject_points' as total_points,
    e.properties->>'num_games' as total_games

from vertices v join edges e
    on v.identifier = e.subject_identifier
    and v.type = e.subject_type

where e.object_type = 'player'::vertex_type
