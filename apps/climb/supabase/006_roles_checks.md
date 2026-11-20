# Checking 006_roles.sql by hand

The Dart copy of the rules is tested in
`packages/hibi_climbing_cloud/test/rights_test.dart`. These checks prove the
database agrees. Run each block in Supabase → SQL Editor; every block ends in
`rollback`, so nothing stays. Replace `<owner>`, `<friend>`, `<other>` with
user ids from `select id, name, is_owner, approved from profiles;`
(`<friend>` and `<other>` approved, neither the owner).

Acting as someone:

```sql
begin;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"<friend>","role":"authenticated"}', true);
-- checks here
rollback;
```

What each check should give:

1. As `<friend>` with no rights: `select grant_right('<other>', 'approve');`
   fails "You can only give a right you hold"; `select can_edit('<a boulder id>');` is false.
2. As `<owner>`: `select grant_right('<friend>', 'edit', '<sector id>');` works.
   Then as `<friend>` (same transaction): `can_edit('<boulder in that sector>')`
   and `can_edit('<problem on it>')` are true, `can_edit('<another sector>')` false;
   `update places set name = name where id = '<boulder in that sector>'` changes 1 row,
   on another sector 0 rows.
3. As `<friend>` after 2: `grant_right('<other>', 'edit', '<boulder in that sector>')`
   works; `grant_right('<other>', 'edit', '<the area above>')` and
   `grant_right('<other>', 'admin')` fail.
4. Give `<other>` edit on the same sector as `<friend>`; as `<friend>`,
   `revoke_right('<that grant id>')` fails "They are at your level or above".
   On a boulder inside the sector it works.
5. As an admin (not owner): `revoke_right` on another admin's grant fails;
   `set_approved('<owner>', false)` fails "Nobody can block the owner";
   `update profiles set is_owner = true where id = auth.uid()` is refused
   (only `name` is writable).
6. As `<owner>`: `revoke_right` on anyone's grant works.
7. `update places set created_by = auth.uid() where id = '<someone else''s place you may edit>'`
   leaves `created_by` unchanged.
8. As `<friend>` with only an approve grant: `set_approved('<waiting id>', true)`
   works; `set_approved('<someone holding a right>', false)` fails.
