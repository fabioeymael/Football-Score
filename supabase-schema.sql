create extension if not exists pgcrypto;

create or replace function public.jsonb_uint_between(value jsonb, min_value integer, max_value integer)
returns boolean
language sql
immutable
as $$
  select
    jsonb_typeof(value) = 'number'
    and value::text ~ '^[0-9]+$'
    and (value::text)::integer between min_value and max_value;
$$;

create or replace function public.valid_team_stats(stats jsonb)
returns boolean
language sql
immutable
as $$
  select
    jsonb_typeof(stats) = 'object'
    and stats ?& array['score', 'shotsOnTarget', 'shotsMissed', 'fouls']
    and jsonb_object_length(stats) = 4
    and public.jsonb_uint_between(stats->'score', 0, 99)
    and public.jsonb_uint_between(stats->'shotsOnTarget', 0, 200)
    and public.jsonb_uint_between(stats->'shotsMissed', 0, 200)
    and public.jsonb_uint_between(stats->'fouls', 0, 100);
$$;

create or replace function public.valid_score_events(events jsonb)
returns boolean
language sql
immutable
as $$
  select
    jsonb_typeof(events) = 'array'
    and coalesce(
      (
        select bool_and(
          jsonb_typeof(event) = 'object'
          and event ?& array['timestamp', 'team', 'note']
          and jsonb_object_length(event) = 3
          and (
            event->>'timestamp' = ''
            or event->>'timestamp' ~ '^[0-9]{1,2}:[0-5][0-9]$'
          )
          and event->>'team' in ('home', 'away')
          and length(coalesce(event->>'note', '')) <= 280
        )
        from jsonb_array_elements(events) as event
      ),
      true
    );
$$;

create table if not exists public.games (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  game_datetime timestamptz,
  home_team text not null,
  away_team text not null,
  home_stats jsonb not null,
  away_stats jsonb not null,
  score_events jsonb not null default '[]'::jsonb,
  youtube_summary text
);

alter table public.games
  drop constraint if exists games_home_team_valid,
  drop constraint if exists games_away_team_valid,
  drop constraint if exists games_distinct_teams_valid,
  drop constraint if exists games_home_stats_valid,
  drop constraint if exists games_away_stats_valid,
  drop constraint if exists games_score_events_valid,
  drop constraint if exists games_youtube_summary_length_valid;

alter table public.games
  add constraint games_home_team_valid
    check (length(btrim(home_team)) between 1 and 80),
  add constraint games_away_team_valid
    check (length(btrim(away_team)) between 1 and 80),
  add constraint games_distinct_teams_valid
    check (lower(btrim(home_team)) <> lower(btrim(away_team))),
  add constraint games_home_stats_valid
    check (public.valid_team_stats(home_stats)),
  add constraint games_away_stats_valid
    check (public.valid_team_stats(away_stats)),
  add constraint games_score_events_valid
    check (public.valid_score_events(score_events)),
  add constraint games_youtube_summary_length_valid
    check (youtube_summary is null or length(youtube_summary) <= 6000);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_games_updated_at on public.games;
create trigger trg_games_updated_at
before update on public.games
for each row execute function public.set_updated_at();

alter table public.games enable row level security;

-- Demo-friendly open policy for quick start.
-- Change this to authenticated-only rules when needed.
drop policy if exists "Allow all operations on games" on public.games;
create policy "Allow all operations on games"
on public.games
for all
using (true)
with check (true);
