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
from actor_films;

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
                                      curr_year              as Year,
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

select
    min(actor) as name,
    count(*) as star_years
from actors
where quality_class = 'star'
group by actorid
order by count(*) desc
;