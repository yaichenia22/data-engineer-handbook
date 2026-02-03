insert into users_cumulated
with yesterday as (
    select *
    from users_cumulated
    where date = date('2023-01-30')
)
, today as (
    select
        cast(user_id as text) as user_id,
        date(cast(event_time as timestamp)) as date_active
     from events
     where
         date(cast(event_time as timestamp)) = date('2023-01-31')
        and user_id is not null
     group by user_id, date(cast(event_time as timestamp))
 )
select
    coalesce(t.user_id, y.user_id) as user_id,
    case when y.dates_active is null
        then array[t.date_active]
        when t.date_active is null then y.dates_active
        else array[t.date_active] || y.dates_active
        end
        as dates_active,
    coalesce(t.date_active, y.date + interval '1 day') as date
from
    today t full outer join
        yesterday y
            on t.user_id = y.user_id
;

select *
from users_cumulated
where date = date('2023-01-31')
;

drop table if exists users_cumulated;
create table users_cumulated
(
    user_id      text,
--     The list of dates in the past where the user was active
    dates_active date[],
--     The current date for the user
    date         date,
    primary key (user_id, date)
)