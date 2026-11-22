-- Climb step 10 (22/11/26, #516; design in #500): the main guide and the
-- community on one shared set of routes, photos and lines.
--
--   in_guide     on routes, sections and lines: part of the area's main
--                guide. Only place editors set it (and, later, the automatic
--                join of #520). Everything published and not in the guide
--                is "community"; drafts stay private (008).
--   route_lines  each route's line on a photo is a row of its own, with its
--                author, so anyone can draw their route on anyone's photo.
--                topos.lines stays as it was for older app versions.
--   guides       a guide's name and credit (the Devín guide, 2020), one
--                official guide per place for now.
--   stars        a like on anything: a place (area, boulder, route), a
--                section photo, a guide. A route only after you topped it.
--   favourites   your own saved places, photos and guides; only you see them.
--
-- Everything that exists when this runs is in the guide: so far only the
-- owner and editors have made routes.
--
-- Run once in the Supabase SQL editor, after 009. Safe to run again.

-- ---- in the guide ----
do $$
begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'places' and column_name = 'in_guide') then
    alter table public.places add column in_guide boolean not null default false;
    update public.places set in_guide = true;
  end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'topos' and column_name = 'in_guide') then
    alter table public.topos add column in_guide boolean not null default false;
    update public.topos set in_guide = true;
  end if;
end $$;

-- Only editors put things in the guide (or take them out). A new place or
-- section made by an editor starts in it; anyone else's starts outside.
-- Runs as the caller, so the owner-run automatic join passes (see 008).
create or replace function public.guide_rule(op text, scope text, was boolean, now_ boolean) returns boolean
language plpgsql set search_path = public as $$
begin
  if current_user not in ('authenticated', 'anon') then
    return now_;
  end if;
  if op = 'INSERT' then
    return public.can_edit(scope);
  end if;
  if now_ is distinct from was and not public.can_edit(scope) then
    raise exception 'Only a place editor can change what is in the guide.';
  end if;
  return now_;
end $$;

create or replace function public.guard_place_guide() returns trigger
language plpgsql set search_path = public as $$
begin
  new.in_guide := public.guide_rule(tg_op, coalesce(new.parent_id, new.id), case when tg_op = 'UPDATE' then old.in_guide end, new.in_guide);
  return new;
end $$;
drop trigger if exists guard_in_guide on public.places;
create trigger guard_in_guide before insert or update on public.places for each row execute function public.guard_place_guide();

create or replace function public.guard_topo_guide() returns trigger
language plpgsql set search_path = public as $$
begin
  new.in_guide := public.guide_rule(tg_op, new.place_id, case when tg_op = 'UPDATE' then old.in_guide end, new.in_guide);
  return new;
end $$;
drop trigger if exists guard_in_guide on public.topos;
create trigger guard_in_guide before insert or update on public.topos for each row execute function public.guard_topo_guide();

-- ---- route lines ----
create table if not exists public.route_lines (
  id uuid primary key default gen_random_uuid(),
  topo_id uuid not null references public.topos (id) on delete cascade,
  problem_id text not null,
  ord integer not null default 0,
  points jsonb not null default '[]'::jsonb,
  start text not null default 'stand',
  "end" text not null default 'topOut',
  color text not null default '#ffffff',
  via jsonb not null default '[]'::jsonb,
  alone boolean not null default false,
  in_guide boolean not null default false,
  created_by uuid not null default auth.uid() references auth.users on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted boolean not null default false
);
create index if not exists route_lines_updated on public.route_lines (updated_at);
create index if not exists route_lines_topo on public.route_lines (topo_id);
drop trigger if exists touch on public.route_lines;
create trigger touch before update on public.route_lines for each row execute function public.touch_updated_at();

-- the lines already drawn, once
do $$
begin
  if not exists (select 1 from public.route_lines) then
    insert into public.route_lines (topo_id, problem_id, ord, points, start, "end", color, via, alone, in_guide, created_by, created_at)
    select t.id, l.value->>'problem', (l.ordinality - 1)::int, coalesce(l.value->'points', '[]'::jsonb),
           coalesce(l.value->>'start', 'stand'), coalesce(l.value->>'end', 'topOut'), coalesce(l.value->>'color', '#ffffff'),
           coalesce(l.value->'via', '[]'::jsonb), coalesce((l.value->>'alone')::boolean, false), t.in_guide, t.created_by, t.created_at
      from public.topos t, jsonb_array_elements(t.lines) with ordinality l
     where not t.deleted and l.value->>'problem' is not null;
  end if;
end $$;

create or replace function public.guard_line_guide() returns trigger
language plpgsql set search_path = public as $$
begin
  new.in_guide := public.guide_rule(tg_op, (select place_id from public.topos where id = new.topo_id),
                                    case when tg_op = 'UPDATE' then old.in_guide end, new.in_guide);
  return new;
end $$;
drop trigger if exists guard_line_guide on public.route_lines;
create trigger guard_line_guide before insert or update on public.route_lines for each row execute function public.guard_line_guide();

alter table public.route_lines enable row level security;
-- a private route's line is as private as the route
drop policy if exists "read" on public.route_lines;
create policy "read" on public.route_lines for select to authenticated
  using (public.is_approved() and (created_by = auth.uid()
         or not exists (select 1 from public.places p where p.id = problem_id and p.draft and p.created_by <> auth.uid())));
drop policy if exists "add" on public.route_lines;
create policy "add" on public.route_lines for insert to authenticated with check (created_by = auth.uid() and public.is_approved());
drop policy if exists "maker or editor" on public.route_lines;
create policy "maker or editor" on public.route_lines for update to authenticated
  using (public.is_approved() and (created_by = auth.uid() or public.can_edit((select place_id from public.topos where id = topo_id))));

-- ---- guides ----
create table if not exists public.guides (
  id uuid primary key default gen_random_uuid(),
  place_id text not null,
  name text not null check (length(name) between 1 and 120),
  credit text not null default '',
  official boolean not null default true,
  created_by uuid not null default auth.uid() references auth.users on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted boolean not null default false
);
create unique index if not exists guides_one_official on public.guides (place_id) where official and not deleted;
drop trigger if exists touch on public.guides;
create trigger touch before update on public.guides for each row execute function public.touch_updated_at();
alter table public.guides enable row level security;
drop policy if exists "read" on public.guides;
create policy "read" on public.guides for select to authenticated using (public.is_approved());
drop policy if exists "editors add" on public.guides;
create policy "editors add" on public.guides for insert to authenticated with check (created_by = auth.uid() and public.can_edit(place_id));
drop policy if exists "editors change" on public.guides;
create policy "editors change" on public.guides for update to authenticated using (public.can_edit(place_id)) with check (public.can_edit(place_id));

-- the guides already imported: one per boulder they went on
insert into public.guides (place_id, name, credit, created_by)
select distinct on (p.parent_id) p.parent_id, 'Devín', p.source, p.created_by
  from public.places p
 where p.source like 'Devín sprievodca%' and p.parent_id is not null and not p.deleted
   and not exists (select 1 from public.guides g where g.place_id = p.parent_id)
 order by p.parent_id, p.created_at;

-- ---- stars and favourites ----
create table if not exists public.stars (
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  kind text not null check (kind in ('place', 'topo', 'guide')),
  item_id text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, kind, item_id)
);
create index if not exists stars_item on public.stars (kind, item_id);
alter table public.stars enable row level security;
drop policy if exists "read" on public.stars;
create policy "read" on public.stars for select to authenticated using (public.is_approved());
drop policy if exists "own" on public.stars;
create policy "own" on public.stars for insert to authenticated with check (user_id = auth.uid() and public.is_approved());
drop policy if exists "own remove" on public.stars;
create policy "own remove" on public.stars for delete to authenticated using (user_id = auth.uid());

-- a route can only be starred by someone who topped it
create or replace function public.guard_route_star() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.kind = 'place'
     and exists (select 1 from public.places where id = new.item_id and kind = 'problem')
     and not exists (select 1 from public.ticks where user_id = new.user_id and problem_id = new.item_id
                     and outcome in ('flash', 'sent') and not deleted) then
    raise exception 'Top the route first, then star it.';
  end if;
  return new;
end $$;
drop trigger if exists guard_route_star on public.stars;
create trigger guard_route_star before insert on public.stars for each row execute function public.guard_route_star();

-- the old 1-5 stars: 4 or 5 from someone who topped the route becomes a star
insert into public.stars (user_id, kind, item_id, created_at)
select o.user_id, 'place', o.problem_id, now()
  from public.opinions o
 where o.stars >= 4
   and exists (select 1 from public.ticks t where t.user_id = o.user_id and t.problem_id = o.problem_id and t.outcome in ('flash', 'sent') and not t.deleted)
on conflict do nothing;

create table if not exists public.favourites (
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  kind text not null check (kind in ('place', 'topo', 'guide')),
  item_id text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, kind, item_id)
);
alter table public.favourites enable row level security;
drop policy if exists "own" on public.favourites;
create policy "own" on public.favourites for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
