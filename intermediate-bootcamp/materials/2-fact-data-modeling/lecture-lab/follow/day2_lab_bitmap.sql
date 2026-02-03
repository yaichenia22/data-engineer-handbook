with users as (select *
               from users_cumulated
               where date = date('2023-01-31')),
     series as (select * from generate_series('2023-01-01', '2023-01-31', interval '1 day') as series_date),
     place_holder_ints as (
         select case
           when
               dates_active @> array [date(series_date)]
               then cast(pow(2, greatest(32 - (date - date(series_date)), 0)) as bigint)
           else 0 end as placeholder_int_value,
       *
from users
         cross join series
-- where user_id = '137925124111668560'
         )
select
    user_id,
    dates_active,
    sum(placeholder_int_value),
    cast(cast(sum(placeholder_int_value) as bigint) as bit(32)),
    bit_count(cast(cast(sum(placeholder_int_value) as bigint) as bit(32))) > 0 as dim_is_monthly_active,
    bit_count(cast('11111110000000000000000000000000' as bit(32)) &
    cast(cast(sum(placeholder_int_value) as bigint) as bit(32))) > 0 as dim_is_weekly_active,
    bit_count(cast('10000000000000000000000000000000' as bit(32)) &
    cast(cast(sum(placeholder_int_value) as bigint) as bit(32))) > 0 as dim_is_daily_active
from place_holder_ints
group by user_id, dates_active
;

with users as (select *
               from users_cumulated
               where date = date('2023-01-31')),
     series as (select * from generate_series('2023-01-01', '2023-01-31', interval '1 day') as series_date),
     place_holder_ints as (
         select case
           when
               dates_active @> array [date(series_date)]
               then cast(pow(2, greatest(32 - (date - date(series_date)), 0)) as bigint)
           else 0 end as placeholder_int_value,
       *
from users
         cross join series
-- where user_id = '137925124111668560'
         )
select *
from place_holder_ints
;
