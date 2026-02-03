select t.*, gd.*
from fct_game_details gd
         join teams t
              on gd.dim_team_id = t.team_id
;

with players_with_multiple_names as (select dim_player_id, array_agg(distinct dim_player_name) names
                                     from fct_game_details
                                     group by dim_player_id
                                     having count(distinct dim_player_name) > 1)
select fgd.dim_player_id, fgd.dim_player_name
from players_with_multiple_names pm
         join fct_game_details fgd on pm.dim_player_id = fgd.dim_player_id
group by fgd.dim_player_id, fgd.dim_player_name
order by 1
;

with agg_player_pts as (select dim_player_id,
                               min(dim_player_name) as dim_player_name,
                               min(dim_season) as season_start,
                               max(dim_season) as season_end,
                               sum(m_pts) as m_pts_total
                        from fct_game_details
                        group by dim_player_id
                        having sum(m_pts) > 0),
     agg_player_at_home_pts as (select dim_player_id,
                                       sum(m_pts) as m_pts_at_home
                                from fct_game_details
                                where dim_is_playing_at_home is true
                                group by dim_player_id),
     agg_player_away_pts as (select dim_player_id,
                                    sum(m_pts) as m_pts_away
                             from fct_game_details
                             where dim_is_playing_at_home is false
                             group by dim_player_id)
select p.dim_player_id,
       p.dim_player_name,
       p.season_start,
       p.season_end,
       coalesce(phm.m_pts_at_home, 0) as m_pts_at_home,
       round(cast(coalesce(phm.m_pts_at_home, 0) as real) / p.m_pts_total * 100) || '%' as m_pts_at_home_pct,
       coalesce(paw.m_pts_away, 0) as m_pts_away,
       round(cast(coalesce(paw.m_pts_away, 0) as real) / p.m_pts_total * 100) || '%'    as m_pts_away_pct,
       p.m_pts_total,
       m_pts_total / (season_end - season_start + 1) as avg_pts_per_season
from agg_player_pts p
         join
     agg_player_at_home_pts phm on p.dim_player_id = phm.dim_player_id
         join agg_player_away_pts paw
              on phm.dim_player_id = paw.dim_player_id
where p.m_pts_total >= 5000
order by m_pts_total / (season_end - season_start + 1) desc
-- order by cast(coalesce(phm.m_pts_at_home, 0) as real) / p.m_pts_total desc, m_pts_total desc
-- order by (4.0 * COALESCE(phm.m_pts_at_home, 0) * COALESCE(paw.m_pts_away, 0))
--              / (COALESCE(phm.m_pts_at_home, 0) + COALESCE(paw.m_pts_away, 0))
;


select dim_player_name,
       dim_is_playing_at_home,
       count(1)                                                               as num_games,
       sum(m_pts),
--         over (partition by dim_player_name order by dim_is_playing_at_home),
       count(case when dim_not_with_team then 1 end)                          as bailed_num,
       cast(count(case when dim_not_with_team then 1 end) as real) / count(1) as bailed_pct
--        count(case when dim_not_with_team then 1 end) as bailed_num
from fct_game_details
group by 1, 2
order by 1, 2;

select dim_player_id,
       dim_player_name,
       count(m_pts)
       over (partition by dim_player_id ) as non_null_pts_cnt
from fct_game_details
order by non_null_pts_cnt
;

select *
from fct_game_details
where dim_player_id = 1630642
  and m_pts is not null
;

select *
from fct_game_details
where dim_player_name = 'Aamir Simms';

insert into fct_game_details
with deduped as (select g.game_date_est,
                        g.season,
                        g.home_team_id,
                        gd.*,
                        row_number()
                        over (partition by gd.game_id, gd.team_id, gd.player_id order by g.game_date_est) as row_num
                 from game_details gd
                          join games g on gd.game_id = g.game_id)
select game_date_est                                    as dim_game_date,
       season                                           as dim_season,
       team_id                                          as dim_team_id,
       player_id                                        as dim_player_id,
       player_name                                      as dim_player_name,
       start_position                                   as dim_start_position,
       team_id = home_team_id                           as dim_is_playing_at_home,
       coalesce(position('DNP' in comment), 0) > 0      as dim_did_not_play,
       coalesce(position('DND' in comment), 0) > 0      as dim_did_not_dress,
       coalesce(position('NWT' in comment), 0) > 0      as dim_not_with_team,
       cast(split_part(min, ':', 1) as real)
           + cast(split_part(min, ':', 2) as real) / 60 as m_minutes,
       fgm                                              as m_fgm,
       fga                                              as m_fga,
       fg3m                                             as m_fg3m,
       fg3a                                             as m_fg3a,
       ftm                                              as m_ftm,
       fta                                              as m_fta,
       oreb                                             as m_oreb,
       dreb                                             as m_dreb,
       reb                                              as m_reb,
       ast                                              as m_ast,
       stl                                              as m_stl,
       blk                                              as m_blk,
       "TO"                                             as m_turnovers,
       pf                                               as m_pf,
       pts                                              as m_pts,
       plus_minus                                       as m_plus_minus
from deduped
where row_num = 1
;

drop table if exists fct_game_details;
create table fct_game_details
(
    dim_game_date          date,
    dim_season             integer,
    dim_team_id            integer,
    dim_player_id          integer,
    dim_player_name        text,
    dim_start_position     text,
    dim_is_playing_at_home boolean,
    dim_did_not_play       boolean,
    dim_did_not_dress      boolean,
    dim_not_with_team      boolean,
    m_minutes              real,
    m_fgm                  integer,
    m_fga                  integer,
    m_fg3m                 integer,
    m_fg3a                 integer,
    m_ftm                  integer,
    m_fta                  integer,
    m_oreb                 integer,
    m_dreb                 integer,
    m_reb                  integer,
    m_ast                  integer,
    m_stl                  integer,
    m_blk                  integer,
    m_turnovers            integer,
    m_pf                   integer,
    m_pts                  integer,
    m_plus_minus           integer,
    primary key (dim_game_date, dim_team_id, dim_player_id)
)
;
