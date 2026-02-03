select *
from player_seasons;
create type season_stats as
(
    season integer,
    gp     integer,
    pts    real,
    reb    real,
    ast    real
);

create type scoring_class as enum ('star', 'good', 'average', 'bad');
create table players
(
    player_name             text,
    height                  text,
    college                 text,
    country                 text,
    draft_year              text,
    draft_round             text,
    draft_number            text,
    season_stats            season_stats[],
    scoring_class           scoring_class,
    years_since_last_season integer,
    current_season          integer,
    is_active               boolean,
    primary key (player_name, current_season)
);

-- drop table players;
truncate players;

INSERT INTO players

WITH years AS (SELECT *
               FROM generate_series(1996, 2022) AS season),

     p AS (SELECT player_name,
                  min(season) AS first_season
           FROM player_seasons
           GROUP BY player_name),

     players_and_seasons AS (SELECT *
                             FROM p
                                      JOIN years y ON
                                 p.first_season <= y.season),

     windowed AS (SELECT ps.player_name,
                         ps.season,
                         array_remove(
                                         array_agg(
                                         CASE
                                             WHEN p1.season IS NOT NULL THEN
                                                 ROW (
                                                     p1.season,
                                                     p1.gp,
                                                     p1.pts,
                                                     p1.reb,
                                                     p1.ast
                                                     )::season_stats
                                             END
                                                  )
                                         OVER (PARTITION BY ps.player_name ORDER BY COALESCE(ps.season, p1.season) ),
                                         NULL
                         ) AS seasons
                  FROM players_and_seasons ps
                           LEFT JOIN player_seasons p1
                                     ON
                                         ps.player_name = p1.player_name
                                             AND ps.season = p1.season
                  ORDER BY ps.player_name,
                           ps.season),

     static AS (SELECT player_name,
                       max(height)       AS height,
                       max(college)      AS college,
                       max(country)      AS country,
                       max(draft_year)   AS draft_year,
                       max(draft_round)  AS draft_round,
                       max(draft_number) AS draft_number
                FROM player_seasons
                GROUP BY player_name)

SELECT w.player_name,
       s.height,
       s.college,
       s.country,
       s.draft_year,
       s.draft_round,
       s.draft_number,
       seasons                                           AS season_stats,
       CASE
           WHEN (seasons[CARDINALITY(seasons)]).pts > 20 THEN 'star'
           WHEN (seasons[CARDINALITY(seasons)]).pts > 15 THEN 'good'
           WHEN (seasons[CARDINALITY(seasons)]).pts > 10 THEN 'average'
           ELSE 'bad'
           END::scoring_class                            AS scoring_class,
       w.season - (seasons[CARDINALITY(seasons)]).season AS YEAR_since_last_season,
       w.season                                          AS current_season,
       (seasons[CARDINALITY(seasons)]).season = w.season AS is_active
FROM windowed w
         JOIN STATIC s ON w.player_name = s.player_name
;


WITH years AS (SELECT *
               FROM generate_series(1996, 2022) AS season),

     p AS (SELECT player_name,
                  min(season) AS first_season
           FROM player_seasons
           GROUP BY player_name),

     players_and_seasons AS (SELECT *
                             FROM p
                                      JOIN years y ON
                                 p.first_season <= y.season),

     windowed AS (SELECT ps.player_name,
                         ps.season,
                         array_remove(
                                         array_agg(
                                         CASE
                                             WHEN p1.season IS NOT NULL THEN
                                                 ROW (
                                                     p1.season,
                                                     p1.gp,
                                                     p1.pts,
                                                     p1.reb,
                                                     p1.ast
                                                     )::season_stats
                                             END
                                                  )
                                         OVER (PARTITION BY ps.player_name ORDER BY COALESCE(ps.season, p1.season) ),
                                         NULL
                         ) AS seasons
                  FROM players_and_seasons ps
                           LEFT JOIN player_seasons p1
                                     ON
                                         ps.player_name = p1.player_name
                                             AND ps.season = p1.season
                  ORDER BY ps.player_name,
                           ps.season),

     static AS (SELECT player_name,
                       max(height)       AS height,
                       max(college)      AS college,
                       max(country)      AS country,
                       max(draft_year)   AS draft_year,
                       max(draft_round)  AS draft_round,
                       max(draft_number) AS draft_number
                FROM player_seasons
                GROUP BY player_name)

SELECT w.player_name,
       w.seasons                                           AS season_stats,
       CASE
           WHEN (seasons[CARDINALITY(seasons)]).pts > 20 THEN 'star'
           WHEN (seasons[CARDINALITY(seasons)]).pts > 15 THEN 'good'
           WHEN (seasons[CARDINALITY(seasons)]).pts > 10 THEN 'average'
           ELSE 'bad'
           END::scoring_class                            AS scoring_class,
       w.season - (seasons[CARDINALITY(seasons)]).season AS YEAR_since_last_season,
       w.season                                          AS current_season,
       (seasons[CARDINALITY(seasons)]).season = w.season AS is_active
FROM windowed w
         JOIN STATIC s ON w.player_name = s.player_name
;

select *
from players
;

insert into players_scd
with with_previous as (select player_name,
                              current_season,
                              scoring_class,
                              is_active,
                              lag(scoring_class, 1)
                              over (partition by player_name order by current_season)                   as previous_scoring_class,
                              lag(is_active, 1) over (partition by player_name order by current_season) as previous_is_active
                       from players
                       where current_season <= 2021),
     with_indicators as (select *,
                                case
                                    when scoring_class <> previous_scoring_class then 1
                                    when is_active <> previous_is_active then 1
                                    else 0
                                    end as change_indicator
                         from with_previous),
     with_streaks as (select *,
                             sum(change_indicator)
                             over (partition by player_name order by current_season) as streak_identifier
                      from with_indicators)
select player_name,
       scoring_class,
       is_active,
       min(current_season) as start_season,
       max(current_season) as end_season,
       2021                as current_season
from with_streaks
group by player_name, streak_identifier, is_active, scoring_class
order by player_name
-- where current_season = 1996
;

create table players_scd
(
    player_name    text,
    scoring_class  scoring_class,
    is_active      boolean,
    start_season   integer,
    end_season     integer,
    current_season integer,
    primary key (player_name, start_season)
);

drop table players_scd;

select *
from players_scd;

create type scd_type as
(
    scoring_class scoring_class,
    is_active     boolean,
    start_season  integer,
    end_season    integer
);

with last_season_scd as (select *
                         from players_scd
                         where current_season = 2021
                           and end_season = 2021),
     historical_scd as (select player_name,
                               scoring_class,
                               is_active,
                               start_season,
                               end_season
                        from players_scd
                        where current_season = 2021
                          and end_season < 2021),
     this_season_data as (select *
                          from players
                          where current_season = 2022),
     unchanged_records as (select ts.player_name,
                                  ts.scoring_class,
                                  ts.is_active,
                                  ls.start_season,
                                  ts.current_season as end_season
                           from this_season_data ts
                                    join last_season_scd ls
                                         on ls.player_name = ts.player_name
                           where ts.scoring_class = ls.scoring_class
                             and ts.is_active = ls.is_active),
     changed_records as (select ts.player_name,
                                ts.scoring_class,
                                ts.is_active,
                                ts.current_season as start_season,
                                ts.current_season as end_season
                         from this_season_data ts
                                  join last_season_scd ls
                                       on ls.player_name = ts.player_name
                         where (ts.scoring_class <> ls.scoring_class
                             or ts.is_active <> ls.is_active)),
     new_records as (select ts.player_name,
                            ts.scoring_class,
                            ts.is_active,
                            ts.current_season as start_season,
                            ts.current_season as end_season
                     from this_season_data ts
                              left join last_season_scd ls
                                        on ts.player_name = ls.player_name
                     where ls.player_name is null),
     accumulated_player_scd as (select *, 'historical' as source
                                from historical_scd
                                union all
                                select *, 'unchanged' as source
                                from unchanged_records
                                union all
                                select *, 'changed' as source
                                from changed_records
                                union all
                                select *, 'new' as source
                                from new_records)

select *
from accumulated_player_scd
-- where player_name = 'Austin Croshere'
-- where player_name = 'Aaron Brooks'
-- where end_season = 2022
where start_season <= 2006 and end_season >= 2006
;