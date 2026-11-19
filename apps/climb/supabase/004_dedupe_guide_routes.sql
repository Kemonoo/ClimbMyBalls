-- One-off: the Devín guide was imported several times, so each of its routes
-- exists two or three times on the boulder. Keeps one of each (the one the
-- sections' lines point to, else the oldest), moves ascents onto it, and
-- marks the rest deleted. Safe to run again. Run in Supabase → SQL Editor.

drop table if exists guide_dupes;
create temporary table guide_dupes as
with refs as (
  select distinct l->>'problem' as id
  from public.topos t, jsonb_array_elements(t.lines) l
  where not t.deleted
),
ranked as (
  select p.id, p.parent_id, p.details->>'number' as number,
         row_number() over (
           partition by p.parent_id, p.details->>'number'
           order by (p.id in (select id from refs)) desc, p.created_at
         ) as rn
  from public.places p
  where p.kind = 'problem' and not p.deleted and p.source like 'Devín%'
    and coalesce(p.details->>'number', '') <> ''
)
select d.id as dupe, k.id as keep
from ranked d join ranked k
  on k.parent_id is not distinct from d.parent_id and k.number = d.number and k.rn = 1
where d.rn > 1;

update public.ticks t set problem_id = g.keep, updated_at = now()
from guide_dupes g where t.problem_id = g.dupe;

update public.places p set deleted = true, updated_at = now()
from guide_dupes g where p.id = g.dupe;

select count(*) as removed_duplicates from guide_dupes;
drop table guide_dupes;
