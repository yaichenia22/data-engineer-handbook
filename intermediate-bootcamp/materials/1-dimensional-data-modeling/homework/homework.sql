-- 1. DDL for actors table
create type film_role as
(
    filmid text,
    film   text,
    votes  integer,
    rating real
);

create type quality_class as enum ('star', 'good', 'average', 'bad');

create table actors
(
    actor         text,
    actorid       text,
    films         film_role[]   not null,
    quality_class quality_class not null,
    is_active     boolean,
    current_year  integer,
    primary key (actorid, current_year)
);

create index idx_actors_current_year
on actors (current_year);

create index idx_actors_actorid_current_year
on actors (actorid, current_year);


-- 2. Cumulative table generation query

-- Let's create an index on actor_films first
create index idx_actor_films_actor_year_desc
on actor_films (actorid, year desc);

-- Fill the table
insert into actors
with years as (select *
               from generate_series((select min(year)
                                     from actor_films),
                                    (select max(year)
                                     from actor_films)) as year),
     actor_film_as_of_year as (select af.*,
                                      y.year as current_year
                               from years y
                                        join actor_films af
                                             on af.year <= y.year),
     actor_films_as_of_year_agg as (select actorid                        as actorid,
                                           array_agg(row (
                                                         afaoy.filmid,
                                                         afaoy.film,
                                                         afaoy.votes,
                                                         afaoy.rating)::film_role
                                                     order by filmid)     as films,
                                           max(afaoy.year) = current_year as is_active,
                                           current_year
                                    from actor_film_as_of_year afaoy
                                    group by current_year, actorid),
     actor_filming_year_quality_class as (select current_year,
                                                 actorid                           as actorid,
                                                 year                              as films_year,
                                                 case
                                                     when avg(rating) > 8 then 'star'
                                                     when avg(rating) > 7 then 'good'
                                                     when avg(rating) > 6 then 'average'
                                                     else 'bad' end::quality_class as quality_class
                                          from actor_film_as_of_year afaoy
                                          group by current_year, actorid, afaoy.year
                                          order by 1, 2, 3 desc),
     actor_last_active_quality_class as (select distinct on (current_year, actorid) current_year,
                                                                                    actorid,
                                                                                    quality_class
                                         from actor_filming_year_quality_class),
     actor_films_cumulated as (select distinct on (afaoya.actorid, afaoya.current_year) afaoya.actorid,
                                                                                        afaoya.films,
                                                                                        alaqc.quality_class,
                                                                                        afaoya.is_active,
                                                                                        afaoya.current_year
                               from actor_films_as_of_year_agg afaoya
                                        join actor_last_active_quality_class alaqc
                                             on afaoya.actorid = alaqc.actorid and
                                                afaoya.current_year = alaqc.current_year),
     actor_dim as (select distinct on (actorid) actorid, actor
                   from actor_films
                   where actor is not null)
select dim.actor as actor,
       afc.actorid,
       afc.films,
       afc.quality_class,
       afc.is_active,
       afc.current_year
from actor_films_cumulated afc
         join actor_dim dim on afc.actorid = dim.actorid
;


-- 3. DDL for actors_history_scd table
create table actors_history_scd
(
    actorid       text,
    actor         text,
    quality_class quality_class,
    is_active     boolean,
    start_year    integer,
    end_year      integer,
    current_year  integer,
    primary key (actorid, start_year, current_year)
);


-- 4. Backfill query for actors_history_scd
DO
$$
    DECLARE
        start_year integer := (select min(current_year)
                               from actors);
        end_year   integer := (select max(current_year)
                               from actors);
    BEGIN
        FOR curr_year IN start_year..end_year
            LOOP
                insert into actors_history_scd
                with with_previous as (select actorid,
                                              actor,
                                              current_year,
                                              quality_class,
                                              is_active,
                                              lag(quality_class, 1)
                                              over (partition by actorid order by current_year) as prev_quality_class,
                                              lag(is_active, 1)
                                              over (partition by actorid order by current_year) as prev_is_active
                                       from actors
                                       where current_year <= curr_year),
                     with_indicators as (select *,
                                                case
                                                    when quality_class <> prev_quality_class then 1
                                                    when is_active <> prev_is_active then 1
                                                    else 0
                                                    end as change_indicator
                                         from with_previous),
                     with_streaks as (select *,
                                             sum(change_indicator)
                                             over (partition by actorid order by current_year) as streak_identifier

                                      from with_indicators)
                select actorid,
                       min(actor),
                       quality_class,
                       is_active,
                       min(current_year) as start_year,
                       max(current_year) as end_year,
                       curr_year         as current_year
                from with_streaks
                group by actorid, streak_identifier, quality_class, is_active;
            END LOOP;
    END
$$;


-- 5. Incremental query for actors_history_scd

-- Clean actors_history_scd
truncate actors_history_scd;

-- Backfill scd until 1981
DO
$$
    DECLARE
        start_year integer := (select min(current_year)
                               from actors);
        end_year   integer := (select 1981);
    BEGIN
        FOR curr_year IN start_year..end_year
            LOOP
                insert into actors_history_scd
                with with_previous as (select actorid,
                                              actor,
                                              current_year,
                                              quality_class,
                                              is_active,
                                              lag(quality_class, 1)
                                              over (partition by actorid order by current_year) as prev_quality_class,
                                              lag(is_active, 1)
                                              over (partition by actorid order by current_year) as prev_is_active
                                       from actors
                                       where current_year <= curr_year),
                     with_indicators as (select *,
                                                case
                                                    when quality_class <> prev_quality_class then 1
                                                    when is_active <> prev_is_active then 1
                                                    else 0
                                                    end as change_indicator
                                         from with_previous),
                     with_streaks as (select *,
                                             sum(change_indicator)
                                             over (partition by actorid order by current_year) as streak_identifier

                                      from with_indicators)
                select actorid,
                       actor,
                       quality_class,
                       is_active,
                       min(current_year) as start_year,
                       max(current_year) as end_year,
                       curr_year         as current_year
                from with_streaks
                group by actorid, streak_identifier, actor, quality_class, is_active;
            END LOOP;
    END
$$;

-- Get scd records number per year
select current_year, count(*) as num_records
from actors_history_scd
group by current_year
order by 1 desc;

-- Get scd records as of last_year
with params as (select max(current_year) as last_scd_year from actors_history_scd)
select scd.*
from actors_history_scd scd
         join params p
              on scd.current_year = p.last_scd_year
order by actorid, start_year
;

-- Fill with new actors data as of 1982
insert into actors_history_scd
with params as (select 1982 as curr_year),
     scd_as_of_last_year as (select scd.*
                             from actors_history_scd scd
                                      join params p
                                           on scd.current_year = p.curr_year - 1),
     scd_ongoing_streaks_as_of_last_year as (select actorid,
                                                    actor,
                                                    quality_class,
                                                    is_active,
                                                    start_year,
                                                    end_year
                                             from scd_as_of_last_year
                                             where end_year = current_year),
     this_year_data as (select a.*
                        from actors a
                                 join params p
                                      on a.current_year = p.curr_year),
     unchanged_scd as (select td.actorid,
                              td.actor,
                              td.quality_class,
                              td.is_active,
                              ls.start_year,
                              td.current_year
                       from this_year_data td
                                join scd_ongoing_streaks_as_of_last_year ls
                                     on td.actorid = ls.actorid and td.current_year = ls.end_year + 1
                       where td.quality_class = ls.quality_class
                         and td.is_active = ls.is_active),
     changed_scd as (select td.actorid,
                            td.actor,
                            td.quality_class,
                            td.is_active,
                            td.current_year,
                            td.current_year
                     from this_year_data td
                              join scd_ongoing_streaks_as_of_last_year ls
                                   on td.actorid = ls.actorid and td.current_year = ls.end_year + 1
                     where td.quality_class <> ls.quality_class
                        or td.is_active <> ls.is_active),
     history_scd as (select actorid,
                            actor,
                            quality_class,
                            is_active,
                            start_year,
                            end_year
                     from scd_as_of_last_year scd
                     where not exists(select 1
                                      from unchanged_scd uscd
                                      where scd.actorid = uscd.actorid
                                        and scd.start_year = uscd.start_year)),
     new_scd as (select td.actorid,
                        td.actor,
                        td.quality_class,
                        td.is_active,
                        td.current_year,
                        td.current_year
                 from this_year_data td
                          left join scd_ongoing_streaks_as_of_last_year ls
                                    on td.actorid = ls.actorid and td.current_year = ls.end_year + 1
                 where ls.actorid is null),
     accumulated_scd as (select *, 'history' as source
                         from history_scd
                         union all
                         select *, 'unchanged' as source
                         from unchanged_scd
                         union all
                         select *, 'changed' as source
                         from changed_scd
                         union all
                         select *, 'new' as source
                         from new_scd)
select acc.actorid,
       acc.actor,
       acc.quality_class,
       acc.is_active,
       acc.start_year,
       acc.end_year,
       p.curr_year as current_year
from accumulated_scd acc,
     params p
;

-- Get scd records number per year
select current_year, count(*) as num_records
from actors_history_scd
group by current_year
order by 1 desc;

-- Get scd records as of last_year
with params as (select max(current_year) as last_scd_year from actors_history_scd)
select scd.*
from actors_history_scd scd
         join params p
              on scd.current_year = p.last_scd_year
order by actorid, start_year
;
