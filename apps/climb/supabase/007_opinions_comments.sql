-- Climb, step 7: what climbers think of a route, like TopLogger's route page.
-- opinions: one row per person and route: the grade it felt like, 1-5 stars,
-- tags (crimps, slab, ...) and a project bookmark (all may be empty). comments: a thread under each route.
-- Approved accounts read everything; you write only your own rows; admins
-- may hide any comment. Run in Supabase -> SQL Editor; safe to run again.

create table if not exists public.opinions (
  problem_id text not null,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  grade text not null default '',          -- '' = no vote
  stars smallint not null default 0 check (stars between 0 and 5), -- 0 = none
  tags text[] not null default '{}',       -- 'crimps', 'slab', ...
  project boolean not null default false,  -- marked as a goal
  updated_at timestamptz not null default now(),
  primary key (problem_id, user_id)
);
alter table public.opinions add column if not exists tags text[] not null default '{}';
alter table public.opinions add column if not exists project boolean not null default false;
create index if not exists opinions_problem on public.opinions (problem_id);
drop trigger if exists touch on public.opinions;
create trigger touch before update on public.opinions for each row execute function public.touch_updated_at();

alter table public.opinions enable row level security;
drop policy if exists "read" on public.opinions;
create policy "read" on public.opinions for select to authenticated using (public.is_approved());
drop policy if exists "own insert" on public.opinions;
create policy "own insert" on public.opinions for insert to authenticated with check (user_id = auth.uid() and public.is_approved());
drop policy if exists "own update" on public.opinions;
create policy "own update" on public.opinions for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  problem_id text not null,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  body text not null check (length(body) between 1 and 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted boolean not null default false
);
create index if not exists comments_problem on public.comments (problem_id, created_at);
drop trigger if exists touch on public.comments;
create trigger touch before update on public.comments for each row execute function public.touch_updated_at();

alter table public.comments enable row level security;
drop policy if exists "read" on public.comments;
create policy "read" on public.comments for select to authenticated using (public.is_approved());
drop policy if exists "own insert" on public.comments;
create policy "own insert" on public.comments for insert to authenticated with check (user_id = auth.uid() and public.is_approved());
drop policy if exists "own or admin update" on public.comments;
create policy "own or admin update" on public.comments for update to authenticated
  using (user_id = auth.uid() or public.is_admin()) with check (user_id = auth.uid() or public.is_admin());
