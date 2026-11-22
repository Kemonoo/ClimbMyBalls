-- Climb step 8 (21/11/26, #462 and #467): private routes and the check mark.
--
--   draft     a route only its maker sees, until they publish it. Published
--             routes cannot go back to private (others may have logged them);
--             delete one instead.
--   verified  the check mark: a place editor (006_roles.sql) set it by hand,
--             or 3 different people topped (flashed or sent) the route.
--             Published routes without it show as "unverified".
--
-- Routes that exist when this runs were made by approved people before
-- there was a check mark, so they all start verified.
--
-- Run once in the Supabase SQL editor, after 007. Safe to run again.

do $$
begin
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'places' and column_name = 'verified') then
    alter table public.places add column verified boolean not null default false;
    update public.places set verified = true;
  end if;
end $$;
alter table public.places add column if not exists draft boolean not null default false;

-- Drafts: only their maker reads them.
drop policy if exists "read" on public.places;
create policy "read" on public.places for select to authenticated
  using (public.is_approved() and (not draft or created_by = auth.uid()));

-- Who may set the check mark, and drafts never carry it. Runs as the caller
-- (not security definer), so current_user tells a person (authenticated)
-- from the auto-verify below (the function owner).
create or replace function public.guard_route_status() returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      if new.verified and not public.can_edit(coalesce(new.parent_id, new.id)) then
        new.verified := false;
      end if;
    else
      if new.verified is distinct from old.verified and not public.can_edit(new.id) then
        raise exception 'Only a place editor can verify routes.';
      end if;
      if new.draft and not old.draft then
        raise exception 'A published route cannot become private again; delete it instead.';
      end if;
    end if;
  end if;
  if new.draft then
    new.verified := false;
  end if;
  return new;
end $$;
drop trigger if exists guard_route_status on public.places;
create trigger guard_route_status before insert or update on public.places
  for each row execute function public.guard_route_status();

-- 3 different people topped it: verified.
create or replace function public.auto_verify() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.outcome in ('flash', 'sent') and not new.deleted
     and (select count(distinct user_id) from public.ticks
          where problem_id = new.problem_id and outcome in ('flash', 'sent') and not deleted) >= 3 then
    update public.places set verified = true
     where id = new.problem_id and not verified and not draft and not deleted;
  end if;
  return new;
end $$;
drop trigger if exists auto_verify on public.ticks;
create trigger auto_verify after insert or update on public.ticks
  for each row execute function public.auto_verify();
