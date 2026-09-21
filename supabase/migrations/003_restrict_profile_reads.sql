-- Existing deployments created by 001 allowed every authenticated user to
-- read every profile. Restrict reads to the account owner so the database
-- matches the published privacy policy.

drop policy if exists "Profiles readable by authenticated" on public.profiles;
drop policy if exists "Users read own profile" on public.profiles;

create policy "Users read own profile"
  on public.profiles for select
  to authenticated
  using (auth.uid() = id);
