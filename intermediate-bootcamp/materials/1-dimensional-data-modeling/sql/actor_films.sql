CREATE TABLE actor_films
(
    Actor   TEXT,
    ActorId Text,
    Film    TEXT,
    Year    integer,
    votes   Integer,
    Rating  REAL,
    FilmID  text,
    PRIMARY KEY (ActorId, FilmId)
);

select *
from actor_films
where actor like '%Robert Downey Jr%';

select min(Year), max(Year)
from actor_films;

create type film_role as
(
    filmid text,
    film   text,
    votes  integer,
    rating real
);
-- drop type film_role;

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
-- drop table actors;

create index idx_actor_films_actor_year_desc
on actor_films (actorid, year desc);

create index idx_actors_current_year
on actors (current_year);

create index idx_actors_actorid_current_year
on actors (actorid, current_year);

select
    actorid,
    count(distinct actor) as uniq_actor_names_count
    from actors
group by actorid
having count(distinct actor) > 1
;

select actorid, array_agg(distinct Actor) as names, count(distinct Actor) as names_count
    from actor_films
group by actorid
order by count(distinct Actor) desc
;


select ActorId,
       min(Actor)        as actor,
       array_agg(row (
           FilmID,
           Film,
           votes,
           Rating
           )::film_role) as films,
       1970              as year,
       avg(Rating)       as avg_rating
from actor_films
where Year = 1970
group by ActorId
;

-- truncate actors;

DO
$$
    DECLARE
        start_year integer := (select min(Year)
                               from actor_films);
        end_year   integer := (select max(Year)
                               from actor_films);
    BEGIN
        FOR curr_year IN start_year..end_year
            LOOP
                insert into actors
                with yesterday as (select *
                                   from actors
                                   where current_year = curr_year - 1),
                     today as (select ActorId,
                                      min(Actor)        as Actor,
                                      array_agg(row (
                                          FilmID,
                                          Film,
                                          votes,
                                          Rating
                                          )::film_role) as films,
                                      curr_year         as Year,
                                      avg(Rating)       as Rating
                               from actor_films
                               where Year = curr_year
                               group by ActorId)
                select coalesce(y.actor, t.Actor)           as actor,
                       coalesce(y.actorid, t.ActorId)       as actorid,
                       case
                           when y.films is null
                               then t.films
                           when t.ActorId is not null
                               then y.films ||
                                    t.films
                           else y.films end                 as films,
                       case
                           when t.Rating > 8 then 'star'
                           when t.Rating > 7 then 'good'
                           when t.Rating > 6 then 'average'
                           else 'bad' end::quality_class    as quality_class,
                       t.Year is not null                   as is_active,
                       coalesce(t.Year, y.current_year + 1) as current_year
                from yesterday y
                         full outer join today t
                                         on y.actorid = t.ActorId;
            END LOOP;
    END
$$;

truncate actors;

select *
from actor_films;

insert into actors
with years AS (select *
               from generate_series((select min(year)
                                     from actor_films),
                                    (select max(year)
                                     from actor_films)) as year),
     actor_film_as_of_year as (select af.*,
                                      y.year as current_year
                               from years y
                                        join actor_films af
                                             on af.year <= y.year),
     actor_films_as_of_year_agg as (select ActorId                        as actorid,
                                           array_agg(row (
                                                         afaoy.FilmID,
                                                         afaoy.Film,
                                                         afaoy.votes,
                                                         afaoy.Rating)::film_role
                                                     order by FilmID)     as films,
                                           max(afaoy.Year) = current_year as is_active,
                                           current_year
                                    from actor_film_as_of_year afaoy
                                    group by current_year, ActorId),
     actor_filming_year_quality_class as (select current_year,
                                                 ActorId                           as actorid,
                                                 Year                              as films_year,
                                                 case
                                                     when avg(Rating) > 8 then 'star'
                                                     when avg(Rating) > 7 then 'good'
                                                     when avg(Rating) > 6 then 'average'
                                                     else 'bad' end::quality_class as quality_class
                                          from actor_film_as_of_year afaoy
                                          group by current_year, ActorId, afaoy.Year
                                          order by 1, 2, 3 desc),
     actor_last_active_quality_class as (select distinct on (current_year, actorid) current_year,
                                                                                    actorid,
                                                                                    quality_class
                                         from actor_filming_year_quality_class),
     actor_films_cumulated as (select distinct on (afaoya.ActorId, afaoya.current_year) afaoya.actorid,
                                                                                        afaoya.films,
                                                                                        alaqc.quality_class,
                                                                                        afaoya.is_active,
                                                                                        afaoya.current_year
                               from actor_films_as_of_year_agg afaoya
                                        join actor_last_active_quality_class alaqc
                                             on afaoya.actorid = alaqc.actorid and
                                                afaoya.current_year = alaqc.current_year),
     actor_dim as (select distinct on (actorid) actorid, Actor
                   from actor_films
                   where actor is not null)
select dim.Actor as actor,
       afc.actorid,
       afc.films,
       afc.quality_class,
       afc.is_active,
       afc.current_year
from actor_films_cumulated afc
         join actor_dim dim on afc.actorid = dim.ActorId
;

select actorid,
       min(actor) as name,
       count(*)   as star_years
from actors
where quality_class = 'star' and is_active
group by actorid
order by count(*) desc
;

select *
from actors
where actorid = 'nm0000005'
;
;

select current_year,
       count(actorid),
       avg(cardinality(films))
from actors
group by current_year
order by current_year
;

select current_year,
       count(actorid),
       avg(cardinality(films))
from actors
group by current_year
order by current_year
;