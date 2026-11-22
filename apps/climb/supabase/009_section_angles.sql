-- Climb step 9 (21/11/26, #469): a section's photos from other angles.
--
-- An angle is a section row of its own (its own photo, holds and lines)
-- with angle_of pointing at the section it shows from another side. Anyone
-- approved may add one, like a section; its maker and place editors change it.
--
-- Run once in the Supabase SQL editor, after 008. Safe to run again.

alter table public.topos add column if not exists angle_of uuid references public.topos (id) on delete set null;
create index if not exists topos_angle_of on public.topos (angle_of);
