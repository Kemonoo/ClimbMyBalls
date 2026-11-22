-- Climb step 12 (22/11/26, #520): proven community routes, and the
-- community's way into the main guide.
--
--   proven   a published route 3 different people topped (flash or top) and
--            3 people starred (stars need a top, 010). Proven community
--            routes fill the "+N community routes" folder.
--   joining  a proven community route joins the main guide by itself when
--            its tops + stars beat the average of the guide's routes on the
--            same boulder, and it fits the guide: its line runs through
--            letters on one of the guide's photos. One that doesn't fit
--            waits in the editors' list.
--
-- Checked again whenever a route is topped or starred. Run once in the
-- Supabase SQL editor, after 011. Safe to run again.

alter table public.places add column if not exists proven boolean not null default false;

create or replace function public.route_score(pid text) returns integer
language sql stable security definer set search_path = public as $$
  select (select count(distinct user_id) from public.ticks where problem_id = pid and outcome in ('flash', 'sent') and not deleted)::int
       + (select count(*) from public.stars where kind = 'place' and item_id = pid)::int
$$;

create or replace function public.refresh_route(pid text) returns void
language plpgsql security definer set search_path = public as $$
declare
  r public.places;
  tops int;
  starred int;
  is_proven boolean;
  average numeric;
begin
  select * into r from public.places where id = pid and kind = 'problem';
  if not found or r.deleted then return; end if;
  tops := (select count(distinct user_id) from public.ticks where problem_id = pid and outcome in ('flash', 'sent') and not deleted);
  starred := (select count(*) from public.stars where kind = 'place' and item_id = pid);
  is_proven := not r.draft and tops >= 3 and starred >= 3;
  if is_proven is distinct from r.proven then
    update public.places set proven = is_proven where id = pid;
  end if;
  if not is_proven or r.in_guide then return; end if;

  -- fits the guide: drawn through letters on a guide photo
  if not exists (
    select 1 from public.route_lines l join public.topos t on t.id = l.topo_id
     where l.problem_id = pid and not l.deleted and t.in_guide and not t.deleted
       and jsonb_array_length(l.via) >= 2
       and not exists (select 1 from jsonb_array_elements_text(l.via) v(label)
                       where not exists (select 1 from jsonb_array_elements(t.marks) m where m->>'label' = v.label))
  ) then
    return;
  end if;

  -- better than the guide's average route on this boulder
  select avg(public.route_score(p.id)) into average
    from public.places p
   where p.parent_id = r.parent_id and p.kind = 'problem' and p.in_guide and not p.deleted and not p.draft and p.id <> pid;
  if tops + starred > coalesce(average, 0) then
    update public.places set in_guide = true where id = pid;
    update public.route_lines set in_guide = true
     where problem_id = pid and topo_id in (select id from public.topos where in_guide);
  end if;
end $$;

create or replace function public.refresh_route_on_tick() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.refresh_route(coalesce(new.problem_id, old.problem_id));
  return null;
end $$;
drop trigger if exists refresh_route on public.ticks;
create trigger refresh_route after insert or update on public.ticks for each row execute function public.refresh_route_on_tick();

create or replace function public.refresh_route_on_star() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(new.kind, old.kind) = 'place' then
    perform public.refresh_route(coalesce(new.item_id, old.item_id));
  end if;
  return null;
end $$;
drop trigger if exists refresh_route on public.stars;
create trigger refresh_route after insert or delete on public.stars for each row execute function public.refresh_route_on_star();

-- the routes there are now
select public.refresh_route(id) from public.places where kind = 'problem' and not deleted;
