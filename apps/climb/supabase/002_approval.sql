-- Climb: new accounts wait for approval; at most 30 accounts (ADR 0021,
-- issue #415). Paste into Supabase → SQL Editor → Run, after schema.sql.
-- Safe to run again.
--
-- Anyone can sign up, but until an admin approves them they can read and
-- write nothing except their own profile (to see that they're waiting).
-- The oldest account (the owner's) becomes the first admin.

alter table public.profiles add column if not exists approved boolean not null default false;
alter table public.profiles add column if not exists is_admin boolean not null default false;

update public.profiles set approved = true, is_admin = true
where id = (select id from auth.users order by created_at limit 1);

create or replace function public.is_approved() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select approved from public.profiles where id = auth.uid()), false)
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false)
$$;

-- Admins approve or block an account. Nobody can approve themselves.
create or replace function public.set_approved(uid uuid, yes boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Only an admin can approve accounts'; end if;
  if uid = auth.uid() then raise exception 'You cannot change your own approval'; end if;
  update public.profiles set approved = yes where id = uid;
end $$;
revoke all on function public.set_approved(uuid, boolean) from public, anon;
grant execute on function public.set_approved(uuid, boolean) to authenticated;

-- At most 30 accounts.
create or replace function public.limit_accounts() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from auth.users) >= 30 then
    raise exception 'Climb is full (30 accounts). Ask the owner.';
  end if;
  return new;
end $$;
drop trigger if exists limit_accounts on auth.users;
create trigger limit_accounts before insert on auth.users for each row execute function public.limit_accounts();

-- Profiles: you can change only your name; approval goes through set_approved.
revoke update on public.profiles from authenticated;
grant update (name) on public.profiles to authenticated;
drop policy if exists "read" on public.profiles;
create policy "read" on public.profiles for select to authenticated using (id = auth.uid() or public.is_approved());

-- Everything else needs an approved account.
drop policy if exists "read" on public.places;
create policy "read" on public.places for select to authenticated using (public.is_approved());
drop policy if exists "add" on public.places;
create policy "add" on public.places for insert to authenticated with check (created_by = auth.uid() and public.is_approved());
drop policy if exists "creator edits" on public.places;
create policy "creator edits" on public.places for update to authenticated using (created_by = auth.uid() and public.is_approved()) with check (created_by = auth.uid());

drop policy if exists "read" on public.topos;
create policy "read" on public.topos for select to authenticated using (public.is_approved());
drop policy if exists "add" on public.topos;
create policy "add" on public.topos for insert to authenticated with check (created_by = auth.uid() and public.is_approved());
drop policy if exists "creator edits" on public.topos;
create policy "creator edits" on public.topos for update to authenticated using (created_by = auth.uid() and public.is_approved()) with check (created_by = auth.uid());

drop policy if exists "read" on public.sessions;
create policy "read" on public.sessions for select to authenticated using (public.is_approved());
drop policy if exists "own insert" on public.sessions;
create policy "own insert" on public.sessions for insert to authenticated with check (user_id = auth.uid() and public.is_approved());

drop policy if exists "read" on public.ticks;
create policy "read" on public.ticks for select to authenticated using (public.is_approved());
drop policy if exists "own insert" on public.ticks;
create policy "own insert" on public.ticks for insert to authenticated with check (user_id = auth.uid() and public.is_approved());

drop policy if exists "topo photos: upload own" on storage.objects;
create policy "topo photos: upload own" on storage.objects for insert to authenticated
  with check (bucket_id = 'topos' and (storage.foldername(name))[1] = auth.uid()::text and public.is_approved());

-- New profiles: the very first account is the owner (approved, admin);
-- everyone after waits.
create or replace function public.make_profile() returns trigger
language plpgsql security definer set search_path = public as $$
declare first boolean := not exists (select 1 from public.profiles);
begin
  insert into public.profiles (id, name, approved, is_admin)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)), first, first)
  on conflict (id) do nothing;
  return new;
end $$;
