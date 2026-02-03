-- 2. A DDL for an user_devices_cumulated table

create type browser_type_activity as
(
    browser_type text,
    activity     date[]
);

drop table if exists user_devices_cumulated;
create table user_devices_cumulated
(
    user_id                  text,
--     The list of dates in the past where the user was active grouped by browser_type.
--     Each element of array is a mapping entry of browser_type -> active dates of the browser_type
    device_activity_datelist browser_type_activity[],
--     The current date for the user
    date                     date,
    primary key (user_id, date)
)
;

-- 3. A cumulative query to generate device_activity_datelist from events

truncate user_devices_cumulated;

insert into user_devices_cumulated
with event_preprocessed
         as (select distinct
        on (
        e.event_time,
        e.user_id,
        e.host,
        e.url
        ) coalesce(d.browser_type, 'Unknown')          as browser_type,
          cast(e.event_time as timestamp)              as event_timestamp,
          date(cast(e.event_time as timestamp))        as event_date,
          e.url,
          e.referrer,
          coalesce(cast(e.user_id as text), 'Unknown') as user_id,
          cast(e.device_id as text)                    as device_id,
          e.host,
          e.event_time
             from events e
                      left join devices d on e.device_id = d.device_id
             where e.user_id is not null),
     browser_type_date_activity as (select event_date,
                                           user_id,
                                           browser_type
                                    from event_preprocessed
                                    group by event_date, user_id, browser_type),
     dates as (select date::date
               from generate_series(
                            (select min(event_date)::timestamp
                             from browser_type_date_activity),
                            (select max(event_date)::timestamp
                             from browser_type_date_activity),
                            '1 day'
                    ) as date),
     browser_type_date_activity_cumulated as (select a.user_id                    as user_id,
                                                     row (
                                                         a.browser_type,
                                                         array_agg(a.event_date order by a.event_date desc)
                                                         )::browser_type_activity as browser_type_activity,
                                                     d.date                       as date
                                              from dates d
                                                       join browser_type_date_activity a on a.event_date <= d.date
                                              group by a.user_id, a.browser_type, d.date)
select user_id,
       array_agg(browser_type_activity order by browser_type_activity) as device_activity_datelist,
       date
from browser_type_date_activity_cumulated
group by user_id, date
;


-- 4. A datelist_int generation query

drop type if exists browser_type_activity_int;
create type browser_type_activity_int as
(
    browser_type text,
    activity     bigint
);

with date_bounds as (select max(date) as   end_date,
                            max(date) - 32 start_date
                     from user_devices_cumulated),
     user_devices_activity as (select user_id, device_activity_datelist, date
                               from user_devices_cumulated
                               where date = (select end_date from date_bounds)),
     date_series as (select *
                     from generate_series(
                                  (select start_date from date_bounds),
                                  (select end_date from date_bounds),
                                  '1 day'
                          ) as s_date),
     user_browser_type_activity as (select u.user_id,
                                           a.browser_type,
                                           a.activity,
                                           u.date
                                    from user_devices_activity u
                                             cross join lateral unnest(device_activity_datelist) as a),
     user_browser_type_activity_placeholder_int as (select case
                                                               when a.activity @> array [date(s.s_date)]
                                                                   then cast(pow(2, greatest(32 - (a.date - date(s.s_date)), 0)) as bigint)
                                                               else 0
                                                               end as activity_int,
                                                           *
                                                    from user_browser_type_activity a
                                                             cross join date_series s),
     user_browser_type_activity_int as (select browser_type,
                                               user_id,
                                               min(activity)     as activity,
                                               sum(activity_int) as datelist_int
                                        from user_browser_type_activity_placeholder_int
                                        group by browser_type, user_id),
     user_browser_type_postprocessed as (select browser_type,
                                                user_id,
                                                b.end_date,
                                                activity,
                                                datelist_int,
                                                cast(cast(datelist_int as bigint) as bit(32)) as datelist_bit,
                                                bit_count(
                                                        cast(
                                                                cast(datelist_int as bigint) as bit(32)) &
                                                        cast(((1::bigint <<
                                                               (b.end_date::date
                                                                   -
                                                                (b.end_date::date - interval '1 month')::date
                                                                   )) -
                                                              1) as bit(32))
                                                ) >
                                                0                                             as dim_is_monthly_active,
                                                bit_count(
                                                        cast(
                                                                cast(datelist_int as bigint) as bit(32)) &
                                                        cast('11111110000000000000000000000000' as bit(32))
                                                ) >
                                                0                                             as dim_is_weekly_active,
                                                bit_count(
                                                        cast(
                                                                cast(datelist_int as bigint) as bit(32)) &
                                                        cast('10000000000000000000000000000000' as bit(32))
                                                ) >
                                                0                                             as dim_is_daily_active
                                         from user_browser_type_activity_int,
                                              date_bounds b)
select user_id,
       array_agg(row (browser_type, datelist_int)::browser_type_activity_int) as datelist_int,
       end_date
from user_browser_type_postprocessed
group by user_id, end_date
;


-- 5. A DDL for hosts_cumulated table

drop table if exists hosts_cumulated;
create table hosts_cumulated
(
    host                   text,
    host_activity_datelist date[],
    date                   date,
    primary key (host, date)
);


-- 6. The incremental query to generate host_activity_datelist

insert into hosts_cumulated
with today as (select date('2023-01-01') as date), -- incrementally change this
     active_hosts_today as (select distinct host
                            from events,
                                 today
                            where date(event_time) = today.date),
     yesterday_hosts_cumulated as (select h.*
                                   from hosts_cumulated h,
                                        today t
                                   where h.date = t.date - 1)
select coalesce(t.host, y.host)        as host,
       case
           when t.host is not null and y.host is not null then
               array [today.date] || y.host_activity_datelist
           when t.host is null then y.host_activity_datelist
           else array [today.date] end as host_activity_datelist,
       today.date
from today,
     active_hosts_today t
         full outer join yesterday_hosts_cumulated y on t.host = y.host
;


-- 7. A monthly, reduced fact table DDL host_activity_reduced

drop table if exists host_activity_reduced;
create table host_activity_reduced
(
    month                 text,
    host                  text,
    hit_array             integer[],
    unique_visitors_array integer[],
    date                  date,
    primary key (month, host, date)
);


-- 8. An incremental query that loads host_activity_reduced day-by-day

insert into host_activity_reduced
with today as (select date('2023-01-01') as date), -- incrementally change this
     host_activity_today as (select host,
                                    count(1)                as hits,
                                    count(distinct user_id) as unique_visitors
                             from events,
                                  today
                             where date(event_time) = today.date
                             group by host)
        ,
     yesterday_host_activity_reduced as (select h.*
                                         from host_activity_reduced h,
                                              today t
                                         where h.month = to_char(t.date, 'YYYY-MM')
                                           and h.date = t.date - interval '1 day')
select to_char(today.date, 'YYYY-MM')         as month,
       coalesce(y.host, t.host)               as host,
       case
           when t.host is not null and y.host is not null then
               array [t.hits] || y.hit_array
           when t.host is null then y.hit_array
           else array [t.hits] end            as hit_array,
       case
           when t.host is not null and y.host is not null then
               array [t.unique_visitors] || y.unique_visitors_array
           when t.host is null then y.unique_visitors_array
           else array [t.unique_visitors] end as unique_visitors_array,
       today.date
from today,
     yesterday_host_activity_reduced y
         full outer join host_activity_today t
                         on y.host = t.host
;
