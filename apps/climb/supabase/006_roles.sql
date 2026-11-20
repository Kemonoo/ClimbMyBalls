-- Climb, step 6: rights you can hand to friends (issue #439).
-- Paste into Supabase → SQL Editor → Run, after 005. Safe to run again.
--
-- Who may do what:
--   owner    the account that made Climb (profiles.is_owner). Every right;
--            nobody can change or take away its rights. Only this SQL editor
--            can move it.
--   admin    every right except touching the owner.
--   approve  lets new accounts in.
--   edit     changes and deletes places and topos inside one place (an area
--            or gym, a sector or wall, a boulder) and everything under it
--            (the places.parent_id chain).
-- Anyone approved can still add places and change what they made.
--
-- Handing out: you can give the same right or a lesser one (edit on a place
-- inside yours). Taking away: only from people below you. Owner > admin >
-- everyone else; an approver can't take approve from another approver; an
-- editor can take edit away only inside their place and only from someone
-- whose own edit doesn't reach as high. You can always give up your own.
-- The same rules live in packages/hibi_climbing_cloud/lib/src/rights.dart
-- (the app uses them to show only the buttons that will work).

-- The owner: today's admin flag becomes the owner flag.
alter table public.profiles add column if not exists is_owner boolean not null default false;
update public.profiles set is_owner = true where is_admin and not is_owner;

create table if not exists public.grants (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  kind text not null check (kind in ('edit', 'approve', 'admin')),
  place_id text,
  granted_by uuid references auth.users on delete set null,
  created_at timestamptz not null default now(),
  check ((kind = 'edit') = (place_id is not null))
);
create unique index if not exists grants_one on public.grants (user_id, kind, coalesce(place_id, ''));
create index if not exists grants_user on public.grants (user_id);
alter table public.grants enable row level security;

-- Everyone let in sees who holds what (the Friends tab shows it). Writes go
-- only through grant_right / revoke_right below.
revoke insert, update, delete on public.grants from anon, authenticated;
grant select on public.grants to authenticated;
drop policy if exists "read" on public.grants;
create policy "read" on public.grants for select to authenticated using (public.is_approved());

-- Helpers. All take the user explicitly so the hierarchy checks can ask
-- about someone else; the no-argument forms mean "me".
create or replace function public.is_owner(uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_owner from public.profiles where id = uid), false)
$$;

create or replace function public.holds(uid uuid, k text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select approved from public.profiles where id = uid), false)
     and exists (select 1 from public.grants where user_id = uid and kind = k)
$$;

-- The place and every place above it (ids, including a bundled
-- OpenStreetMap parent that has no row here).
create or replace function public.place_chain(pid text) returns setof text
language sql stable security definer set search_path = public as $$
  with recursive up(id, depth) as (
    select pid, 0
    union all
    select p.parent_id, up.depth + 1 from up join public.places p on p.id = up.id
    where p.parent_id is not null and up.depth < 20
  )
  select id from up
$$;

-- Keeps is_admin() (used by the policies of step 3) working: the owner or
-- anyone holding admin.
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner(auth.uid()) or public.holds(auth.uid(), 'admin')
$$;

create or replace function public.can_approve(uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner(uid) or public.holds(uid, 'admin') or public.holds(uid, 'approve')
$$;

-- An edit grant of uid's on pid or above it.
create or replace function public.edit_reach(uid uuid, pid text) returns boolean
language sql stable security definer set search_path = public as $$
  select pid is not null
     and coalesce((select approved from public.profiles where id = uid), false)
     and exists (select 1 from public.grants g where g.user_id = uid and g.kind = 'edit'
                 and g.place_id in (select public.place_chain(pid)))
$$;

create or replace function public.can_edit(pid text, uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner(uid) or public.holds(uid, 'admin') or public.edit_reach(uid, pid)
$$;

-- Could `who` hand out this right? (the owner and admins anything; an
-- approver approve; an editor edit on their place or inside it)
create or replace function public.covers(who uuid, k text, pid text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner(who) or public.holds(who, 'admin')
      or (k = 'approve' and public.holds(who, 'approve'))
      or (k = 'edit' and public.edit_reach(who, pid))
$$;

-- Is `target` below `who` for this right, so `who` may take it away?
create or replace function public.outranks(who uuid, target uuid, k text, pid text) returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when public.is_owner(target) then false
    when public.is_owner(who) then true
    when public.holds(target, 'admin') then false
    when public.holds(who, 'admin') then true
    when k = 'edit' then exists (
      -- one of who's edit places sits strictly above pid, and target's own
      -- edit doesn't reach that place
      select 1 from public.grants g
      where g.user_id = who and g.kind = 'edit'
        and coalesce((select approved from public.profiles where id = who), false)
        and g.place_id <> pid and g.place_id in (select public.place_chain(pid))
        and not public.edit_reach(target, g.place_id))
    else false
  end
$$;

create or replace function public.grant_right(uid uuid, k text, pid text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if k not in ('edit', 'approve', 'admin') then raise exception 'Unknown right %', k; end if;
  if (k = 'edit') <> (pid is not null) then raise exception 'Edit rights need a place, others none'; end if;
  if uid = auth.uid() then raise exception 'You cannot give yourself rights'; end if;
  if public.is_owner(uid) then raise exception 'The owner already has every right'; end if;
  if not coalesce((select approved from public.profiles where id = uid), false) then
    raise exception 'Let them in first';
  end if;
  if not public.covers(auth.uid(), k, pid) then raise exception 'You can only give a right you hold'; end if;
  insert into public.grants (user_id, kind, place_id, granted_by) values (uid, k, pid, auth.uid())
  on conflict do nothing;
end $$;

create or replace function public.revoke_right(grant_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare g public.grants;
begin
  select * into g from public.grants where id = grant_id;
  if not found then return; end if;
  if g.user_id <> auth.uid() and not public.outranks(auth.uid(), g.user_id, g.kind, g.place_id) then
    raise exception 'They are at your level or above';
  end if;
  delete from public.grants where id = grant_id;
end $$;

revoke all on function public.grant_right(uuid, text, text) from public, anon;
revoke all on function public.revoke_right(uuid) from public, anon;
grant execute on function public.grant_right(uuid, text, text) to authenticated;
grant execute on function public.revoke_right(uuid) to authenticated;

-- Approving: anyone with the approve right. Blocking someone already let in
-- takes outranking them (an approver can block only people with no rights).
create or replace function public.set_approved(uid uuid, yes boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.can_approve(auth.uid()) then raise exception 'You cannot approve accounts'; end if;
  if uid = auth.uid() then raise exception 'You cannot change your own approval'; end if;
  if public.is_owner(uid) then raise exception 'Nobody can block the owner'; end if;
  if not yes and exists (select 1 from public.grants where user_id = uid)
     and not (public.is_owner(auth.uid()) or (public.holds(auth.uid(), 'admin') and not public.holds(uid, 'admin'))) then
    raise exception 'They hold rights at your level or above';
  end if;
  update public.profiles set approved = yes where id = uid;
end $$;

-- New profiles: the very first account is the owner.
create or replace function public.make_profile() returns trigger
language plpgsql security definer set search_path = public as $$
declare first boolean := not exists (select 1 from public.profiles);
begin
  insert into public.profiles (id, name, approved, is_admin, is_owner)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)), first, first, first)
  on conflict (id) do nothing;
  return new;
end $$;

-- Nobody's edit takes over a place or topo: created_by stays as it was.
create or replace function public.keep_creator() returns trigger
language plpgsql as $$
begin
  new.created_by := old.created_by;
  return new;
end $$;
drop trigger if exists keep_creator on public.places;
create trigger keep_creator before update on public.places for each row execute function public.keep_creator();
drop trigger if exists keep_creator on public.topos;
create trigger keep_creator before update on public.topos for each row execute function public.keep_creator();

-- A scoped editor may change a place inside their reach, and move it only to
-- a parent also inside their reach. (Inside a policy, reading places sees
-- the row as it was before the update.)
create or replace function public.may_save_place(pid text, new_parent text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_admin()
      or (select created_by from public.places where id = pid) = auth.uid()
      or (public.can_edit(pid)
          and (new_parent is not distinct from (select parent_id from public.places where id = pid)
               or public.can_edit(new_parent)))
$$;

drop policy if exists "creator edits" on public.places;
create policy "creator edits" on public.places for update to authenticated
  using (public.is_approved() and (created_by = auth.uid() or public.can_edit(id)))
  with check (public.may_save_place(id, parent_id));

drop policy if exists "creator edits" on public.topos;
create policy "creator edits" on public.topos for update to authenticated
  using (public.is_approved() and (created_by = auth.uid() or public.can_edit(place_id)))
  with check (created_by = auth.uid() or public.can_edit(place_id));

-- Topo photos: your own folder as before, and anyone who may edit the topo
-- a photo belongs to may replace or remove it.
drop policy if exists "topo photos: replace own" on storage.objects;
create policy "topo photos: replace own" on storage.objects for update to authenticated
  using (bucket_id = 'topos' and public.is_approved() and (
    (storage.foldername(name))[1] = auth.uid()::text
    or exists (select 1 from public.topos t where (t.photo_path = objects.name or t.original_path = objects.name) and public.can_edit(t.place_id))));
drop policy if exists "topo photos: remove" on storage.objects;
create policy "topo photos: remove" on storage.objects for delete to authenticated
  using (bucket_id = 'topos' and public.is_approved() and (
    (storage.foldername(name))[1] = auth.uid()::text
    or exists (select 1 from public.topos t where (t.photo_path = objects.name or t.original_path = objects.name) and public.can_edit(t.place_id))));

select (select count(*) from public.profiles where is_owner) as owners, (select count(*) from public.grants) as grants;
