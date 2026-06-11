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
    and (select count(*) from jsonb_object_keys(stats)) = 4
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
          and (select count(*) from jsonb_object_keys(event)) = 3
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
  owner_id uuid,
  game_datetime timestamptz,
  home_team text not null,
  away_team text not null,
  home_stats jsonb not null,
  away_stats jsonb not null,
  score_events jsonb not null default '[]'::jsonb,
  youtube_summary text
);

alter table public.games
  add column if not exists owner_id uuid;

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

create or replace function public.set_games_owner_id()
returns trigger
language plpgsql
as $$
begin
  if new.owner_id is null then
    new.owner_id = auth.uid();
  end if;

  return new;
end;
$$;

drop trigger if exists trg_games_updated_at on public.games;
create trigger trg_games_updated_at
before update on public.games
for each row execute function public.set_updated_at();

drop trigger if exists trg_games_owner_id on public.games;
create trigger trg_games_owner_id
before insert on public.games
for each row execute function public.set_games_owner_id();

alter table public.games enable row level security;
alter table public.games force row level security;

drop policy if exists "Users can read own games" on public.games;
drop policy if exists "Users can insert own games" on public.games;
drop policy if exists "Users can update own games" on public.games;
drop policy if exists "Users can delete own games" on public.games;
drop policy if exists "Allow all operations on games" on public.games;
create policy "Users can read own games"
on public.games
for select
using (owner_id = auth.uid());

create policy "Users can insert own games"
on public.games
for insert
with check (owner_id = auth.uid());

create policy "Users can update own games"
on public.games
for update
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

create policy "Users can delete own games"
on public.games
for delete
using (owner_id = auth.uid());
