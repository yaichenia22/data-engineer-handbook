-- 1. A query to deduplicate game_details from Day 1 so there's no duplicates

-- extension to unaccent letters during name normalization
CREATE EXTENSION IF NOT EXISTS unaccent;

-- name normalization function
CREATE OR REPLACE FUNCTION normalize_person_name(person_name text)
    RETURNS text
    LANGUAGE sql
    IMMUTABLE
    PARALLEL SAFE
AS
$$
SELECT lower(
               trim(
                       regexp_replace(
                               regexp_replace(
                                       regexp_replace(
                                               unaccent(person_name),
                                               '[^[:alpha:]]+',
                                               ' ',
                                               'g'
                                       ),
                                       '(^|[[:space:]])([A-Z])([A-Z])([[:space:]]|$)',
                                       '\1\2 \3\4',
                                       'g'
                               ),
                               '[[:space:]]+',
                               ' ',
                               'g'
                       )
               )
       );
$$;

-- index for faster query
CREATE INDEX ON game_details (normalize_person_name(player_name));

-- surrogate key for a fact record of game participation by a player. This encapsulates game_date, contenders ids, and normalized player name.
-- this key helps us to detect duplicates of the fact even if it has multiple records with different game_id,
-- swapped home_team and visitor_team, or misspelled player name
CREATE OR REPLACE FUNCTION surrogate_game_player_key(
    game_date date,
    team_id_1 int,
    team_id_2 int,
    player_name_norm text
)
    RETURNS bigint
    LANGUAGE sql
    IMMUTABLE
    PARALLEL SAFE
AS
$$
SELECT hashtextextended(
               concat_ws(
                       '§', -- safe delimiter
                       game_date::text,
                       LEAST(team_id_1, team_id_2)::text,
                       GREATEST(team_id_1, team_id_2)::text,
                       player_name_norm
               ),
               0
       );
$$;

-- deduplication query
with game_details_player_name_aligned as (select game_id,
                                                 team_id,
                                                 team_abbreviation,
                                                 team_city,
                                                 player_id,
                                                 first_value(player_name)
                                                 over (partition by player_id order by length(player_name) desc) as player_name,
                                                 nickname,
                                                 start_position,
                                                 comment,
                                                 min,
                                                 fgm,
                                                 fga,
                                                 fg_pct,
                                                 fg3m,
                                                 fg3a,
                                                 fg3_pct,
                                                 ftm,
                                                 fta,
                                                 ft_pct,
                                                 oreb,
                                                 dreb,
                                                 reb,
                                                 ast,
                                                 stl,
                                                 blk,
                                                 "TO",
                                                 pf,
                                                 pts,
                                                 plus_minus
                                          from game_details),
     game_player_detail_windowed as (select row_number() over w_game_player_normalized                as dup_idx,
                                            first_value(g.game_date_est) over w_game                  as game_date_est,
                                            first_value(g.game_id) over w_game                        as game_id,
                                            first_value(g.game_status_text) over w_game               as game_status_text,
                                            first_value(g.home_team_id) over w_game                   as home_team_id,
                                            first_value(g.visitor_team_id) over w_game                as visitor_team_id,
                                            first_value(g.season) over w_game                         as season,
                                            first_value(g.team_id_home) over w_game                   as team_id_home,
                                            first_value(g.pts_home) over w_game                       as pts_home,
                                            first_value(g.fg_pct_home) over w_game                    as fg_pct_home,
                                            first_value(g.ft_pct_home) over w_game                    as ft_pct_home,
                                            first_value(g.fg3_pct_home) over w_game                   as fg3_pct_home,
                                            first_value(g.ast_home) over w_game                       as ast_home,
                                            first_value(g.reb_home) over w_game                       as reb_home,
                                            first_value(g.team_id_away) over w_game                   as team_id_away,
                                            first_value(g.pts_away) over w_game                       as pts_away,
                                            first_value(g.fg_pct_away) over w_game                    as fg_pct_away,
                                            first_value(g.ft_pct_away) over w_game                    as ft_pct_away,
                                            first_value(g.fg3_pct_away) over w_game                   as fg3_pct_away,
                                            first_value(g.ast_away) over w_game                       as ast_away,
                                            first_value(g.reb_away) over w_game                       as reb_away,
                                            first_value(g.home_team_wins) over w_game                 as home_team_wins,
                                            gd.team_id,
                                            gd.team_abbreviation,
                                            gd.team_city,
                                            first_value(gd.player_id) over w_player_name_normalized   as player_id,
                                            first_value(gd.player_name) over w_player_name_normalized as player_name,
                                            first_value(gd.nickname)
                                            over w_player_name_normalized_ordered_by_nickname         as nickname,
                                            gd.start_position,
                                            gd.comment,
                                            gd.min,
                                            gd.fgm,
                                            gd.fga,
                                            gd.fg_pct,
                                            gd.fg3m,
                                            gd.fg3a,
                                            gd.fg3_pct,
                                            gd.ftm,
                                            gd.fta,
                                            gd.ft_pct,
                                            gd.oreb,
                                            gd.dreb,
                                            gd.reb,
                                            gd.ast,
                                            gd.stl,
                                            gd.blk,
                                            gd."TO",
                                            gd.pf,
                                            gd.pts,
                                            gd.plus_minus
                                     from games g
                                              join game_details_player_name_aligned gd on g.game_id = gd.game_id
                                     window w_game_player_normalized as (
                                             partition by
                                                 surrogate_game_player_key(g.game_date_est,
                                                                           least(g.home_team_id, g.visitor_team_id),
                                                                           greatest(g.home_team_id, g.visitor_team_id),
                                                                           normalize_person_name(gd.player_name))
                                             order by length(gd.player_name) desc
                                             ),
                                            w_game as (
                                                    partition by g.game_date_est,
                                                        least(g.home_team_id, g.visitor_team_id),
                                                        greatest(g.home_team_id, g.visitor_team_id)
                                                    order by g.game_id desc
                                                    ),
                                            w_player_name_normalized as (
                                                    partition by normalize_person_name(gd.player_name)
                                                    order by length(gd.player_name) desc
                                                    ),
                                            w_player_name_normalized_ordered_by_nickname as (
                                                    partition by normalize_person_name(gd.player_name)
                                                    order by length(coalesce(gd.nickname, '')) desc
                                                    )),
     game_player_detail_deduped as (select game_id,
                                           team_id,
                                           team_abbreviation,
                                           team_city,
                                           player_id,
                                           player_name,
                                           nickname,
                                           start_position,
                                           comment,
                                           min,
                                           fgm,
                                           fga,
                                           fg_pct,
                                           fg3m,
                                           fg3a,
                                           fg3_pct,
                                           ftm,
                                           fta,
                                           ft_pct,
                                           oreb,
                                           dreb,
                                           reb,
                                           ast,
                                           stl,
                                           blk,
                                           "TO",
                                           pf,
                                           pts,
                                           plus_minus
                                    from game_player_detail_windowed
                                    where dup_idx = 1)
select *
from game_player_detail_deduped
;
