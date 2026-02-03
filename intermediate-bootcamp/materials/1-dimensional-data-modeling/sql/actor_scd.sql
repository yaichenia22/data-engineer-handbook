select *
from actors;

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

drop table if exists actors_history_scd;

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
                       actor,
                       quality_class,
                       is_active,
                       min(current_year) as start_year,
                       max(current_year) as end_year,
                       curr_year         as current_year
                from with_streaks
                group by actorid, streak_identifier, actor, quality_class, is_active
                order by actorid;
            END LOOP;
    END
$$;

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
                       where current_year <= 1981),
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
       2020              as current_year
from with_streaks
group by actorid, streak_identifier, actor, quality_class, is_active
order by actorid
;

select *
from actors;

truncate actors_history_scd;

select *
from actors_history_scd
where actorid = 'nm0000001'
--   and current_year = 1981
;

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

drop table actors_history_scd;

truncate table actors;

select * from actors;

with scd_streaks_as_of_last_year as (select actorid,
                                            actor,
                                            quality_class,
                                            is_active,
                                            start_year,
                                            end_year
                                     from actors_history_scd
                                     where current_year = 1981
                                       and end_year <= 1980),
     scd_streaks_ended_last_year as (select actorid,
                                            actor,
                                            quality_class,
                                            is_active,
                                            start_year,
                                            end_year
                                     from actors_history_scd
                                     where current_year = 1981
                                       and end_year = 1981),
     this_year_data as (select *
                        from actors
                        where current_year = 1982),
     unchanged_scd as (select td.actorid,
                              td.actor,
                              td.quality_class,
                              td.is_active,
                              ls.start_year,
                              td.current_year
                       from this_year_data td
                                join scd_streaks_ended_last_year ls
                                     on td.actorid = ls.actorid
                       where td.quality_class = ls.quality_class
                         and td.is_active = ls.is_active),
     changed_scd as (select td.actorid,
                            td.actor,
                            td.quality_class,
                            td.is_active,
                            td.current_year,
                            td.current_year
                     from this_year_data td
                              join scd_streaks_ended_last_year ls
                                   on td.actorid = ls.actorid
                     where td.quality_class <> ls.quality_class
                        or td.is_active <> ls.is_active),
     new_scd as (select td.actorid,
                        td.actor,
                        td.quality_class,
                        td.is_active,
                        td.current_year,
                        td.current_year
                 from this_year_data td
                          left join scd_streaks_ended_last_year ls
                                    on td.actorid = ls.actorid
                 where ls.actorid is null),
     accumulated_scd as (select *, 'history' as source
                         from scd_streaks_as_of_last_year
                         union all
                         select *, 'unchanged' as source
                         from unchanged_scd
                         union all
                         select *, 'changed' as source
                         from changed_scd
                         union all
                         select *, 'new' as source
                         from new_scd)
select *
from accumulated_scd
-- where actorid = 'nm0086883'
-- where source = 'new'
order by actorid, start_year
-- offset 500
;

