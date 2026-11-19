-- Climb, step 3: admins edit anything; topos become named sections with an
-- optional second photo; everyone sees who logged a route.
-- Run once in Supabase → SQL Editor, after 002_approval.sql.

-- Sections: a name and an optional second photo (a printed guide's drawing).
alter table public.topos add column if not exists name text not null default '';
alter table public.topos add column if not exists original_path text not null default '';

-- Admins may change or delete (soft) any place or topo; others only their own.
drop policy if exists "creator edits" on public.places;
create policy "creator edits" on public.places for update to authenticated
  using ((created_by = auth.uid() or public.is_admin()) and public.is_approved())
  with check (created_by = auth.uid() or public.is_admin());

drop policy if exists "creator edits" on public.topos;
create policy "creator edits" on public.topos for update to authenticated
  using ((created_by = auth.uid() or public.is_admin()) and public.is_approved())
  with check (created_by = auth.uid() or public.is_admin());

-- Ticks: you change (or soft-delete) only your own.
drop policy if exists "own" on public.ticks;
create policy "own" on public.ticks for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
