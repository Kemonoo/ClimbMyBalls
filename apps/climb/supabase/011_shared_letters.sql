-- Climb step 11 (22/11/26, #519): letters (holds) are the boulder's, not a
-- photo's. Anyone approved may ADD letters to any section photo, so they
-- can draw their route on it; only the photo's maker and place editors
-- move, rename or remove letters, or change anything else about the photo.
--
-- Run once in the Supabase SQL editor, after 010. Safe to run again.

drop policy if exists "anyone adds letters" on public.topos;
create policy "anyone adds letters" on public.topos for update to authenticated
  using (public.is_approved()) with check (public.is_approved());

create or replace function public.guard_topo_letters() returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user in ('authenticated', 'anon')
     and not (old.created_by = auth.uid() or public.can_edit(old.place_id)) then
    -- someone else's photo: letters may only be added, nothing else changes
    if not (new.marks @> old.marks)
       or (to_jsonb(new) - array['marks', 'updated_at']) is distinct from (to_jsonb(old) - array['marks', 'updated_at']) then
      raise exception 'You can add letters to this photo; changing it is for its maker or a place editor.';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists guard_topo_letters on public.topos;
create trigger guard_topo_letters before update on public.topos for each row execute function public.guard_topo_letters();
