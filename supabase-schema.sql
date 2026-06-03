create extension if not exists pgcrypto;

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
