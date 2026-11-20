-- Climb's shared database (docs/climb/plan.md step 7, ADR 0021).
-- Paste into Supabase → SQL Editor → Run. Safe to run again.
--
-- The project was created with "auto-grant" off and RLS on, so every table
-- below grants access explicitly and has its own rules. The app only ever
-- holds the publishable key; these rules are what keep data safe.
--
-- Who can do what:
--   read everything ......... anyone signed in
--   add a place or topo ..... anyone signed in (it is theirs)
--   change a place or topo .. its creator (soft delete: deleted = true)
--   ticks, sessions, profile  only the owner writes

create extension if not exists pgcrypto;

-- updated_at on every change, so the app can fetch only what is new.
create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

-- Profiles: the name friends see. Made when someone signs up.
create table if not exists public.profiles (
  id uuid primary key references auth.users on delete cascade,
  name text not null default '',
  created_at timestamptz not null default now()
);

create or replace function public.make_profile() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.make_profile();

-- Places: areas, sectors, boulders, problems and gym walls
-- (packages/climbing/lib/places/place.dart). parent_id is text with no
-- foreign key, because a parent can be an OpenStreetMap place bundled with
-- the app rather than a row here.
create table if not exists public.places (
  id text primary key,
  parent_id text,
  kind text not null check (kind in ('country','region','area','sector','boulder','problem','gymWall')),
  name text not null check (length(name) between 1 and 120),
  geometry jsonb,
  grade_system text not null default 'font',
  indoor boolean not null default false,
  grade text not null default '',
  details jsonb not null default '{}'::jsonb,
  source text not null default 'manual',
  licence text not null default 'ODbL',
  created_by uuid not null default auth.uid() references auth.users on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted boolean not null default false
);
create index if not exists places_updated on public.places (updated_at);
create index if not exists places_parent on public.places (parent_id);

-- Topos: a photo of a wall with letters and drawn route lines. x and y are
-- 0..1 of the photo. marks: [{"label":"A","x":..,"y":..}]; lines:
-- [{"problem":"<place id>","points":[[x,y],..],"start":"stand|sit","end":"top|arrow","color":"#ffffff"}].
create table if not exists public.topos (
  id uuid primary key default gen_random_uuid(),
  place_id text not null,
  photo_path text not null,
  bearing integer check (bearing between 0 and 359),
  width integer,
  height integer,
  marks jsonb not null default '[]'::jsonb,
  lines jsonb not null default '[]'::jsonb,
  created_by uuid not null default auth.uid() references auth.users on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted boolean not null default false
);
create index if not exists topos_updated on public.topos (updated_at);
create index if not exists topos_place on public.topos (place_id);

-- Sessions: a climbing session as the app's ClimbSession JSON, for the feed.
create table if not exists public.sessions (
  id text primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  start timestamptz not null,
  data jsonb not null,
  updated_at timestamptz not null default now(),
  deleted boolean not null default false
);
create index if not exists sessions_start on public.sessions (start desc);

-- Ticks: one ascent of a problem, with an optional grade vote.
create table if not exists public.ticks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  problem_id text not null,
  day date not null,
  outcome text not null check (outcome in ('flash','sent','tried')),
  grade_vote text not null default '',
  session_id text,
  note text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted boolean not null default false
);
create index if not exists ticks_problem on public.ticks (problem_id);

drop trigger if exists touch on public.places;
create trigger touch before update on public.places for each row execute function public.touch_updated_at();
drop trigger if exists touch on public.topos;
create trigger touch before update on public.topos for each row execute function public.touch_updated_at();
drop trigger if exists touch on public.sessions;
create trigger touch before update on public.sessions for each row execute function public.touch_updated_at();
drop trigger if exists touch on public.ticks;
create trigger touch before update on public.ticks for each row execute function public.touch_updated_at();

-- Rules.
alter table public.profiles enable row level security;
alter table public.places enable row level security;
alter table public.topos enable row level security;
alter table public.sessions enable row level security;
alter table public.ticks enable row level security;

grant select, insert, update on public.profiles, public.places, public.topos, public.sessions, public.ticks to authenticated;

drop policy if exists "read" on public.profiles;
create policy "read" on public.profiles for select to authenticated using (true);
drop policy if exists "own" on public.profiles;
create policy "own" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
drop policy if exists "own insert" on public.profiles;
create policy "own insert" on public.profiles for insert to authenticated with check (id = auth.uid());

drop policy if exists "read" on public.places;
create policy "read" on public.places for select to authenticated using (true);
drop policy if exists "add" on public.places;
create policy "add" on public.places for insert to authenticated with check (created_by = auth.uid());
drop policy if exists "creator edits" on public.places;
create policy "creator edits" on public.places for update to authenticated using (created_by = auth.uid()) with check (created_by = auth.uid());

drop policy if exists "read" on public.topos;
create policy "read" on public.topos for select to authenticated using (true);
drop policy if exists "add" on public.topos;
create policy "add" on public.topos for insert to authenticated with check (created_by = auth.uid());
drop policy if exists "creator edits" on public.topos;
create policy "creator edits" on public.topos for update to authenticated using (created_by = auth.uid()) with check (created_by = auth.uid());

drop policy if exists "read" on public.sessions;
create policy "read" on public.sessions for select to authenticated using (true);
drop policy if exists "own insert" on public.sessions;
create policy "own insert" on public.sessions for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "own" on public.sessions;
create policy "own" on public.sessions for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "read" on public.ticks;
create policy "read" on public.ticks for select to authenticated using (true);
drop policy if exists "own insert" on public.ticks;
create policy "own insert" on public.ticks for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "own" on public.ticks;
create policy "own" on public.ticks for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Topo photos. A public bucket: rock photos aren't private, and public URLs
-- can be cached on the phone. Each person uploads only into their own folder
-- (<user id>/...), and the app shrinks photos to about 250 KB first.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('topos', 'topos', true, 1048576, array['image/jpeg','image/webp'])
on conflict (id) do update set public = true, file_size_limit = 1048576, allowed_mime_types = array['image/jpeg','image/webp'];

drop policy if exists "topo photos: upload own" on storage.objects;
create policy "topo photos: upload own" on storage.objects for insert to authenticated
  with check (bucket_id = 'topos' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "topo photos: replace own" on storage.objects;
create policy "topo photos: replace own" on storage.objects for update to authenticated
  using (bucket_id = 'topos' and (storage.foldername(name))[1] = auth.uid()::text);
