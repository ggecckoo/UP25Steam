-- Yirmibeş — Auth + profiles + game_results
-- Supabase Dashboard → SQL Editor, veya: supabase db push

create extension if not exists "pgcrypto";

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null,
  display_name text not null,
  games_played int not null default 0,
  games_won int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.game_results (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  score int not null,
  placement int not null check (placement between 1 and 4),
  won boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists game_results_user_id_idx on public.game_results (user_id);
create index if not exists game_results_created_at_idx on public.game_results (created_at desc);

-- Yeni auth kullanıcısı → profil satırı
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, display_name)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(
      new.raw_user_meta_data ->> 'display_name',
      split_part(coalesce(new.email, 'oyuncu'), '@', 1)
    )
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_updated_at on public.profiles;
create trigger profiles_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

alter table public.profiles enable row level security;
alter table public.game_results enable row level security;

create policy "Users read own profile"
  on public.profiles for select
  to authenticated
  using (auth.uid() = id);

create policy "Users insert own profile"
  on public.profiles for insert
  to authenticated
  with check (auth.uid() = id);

create policy "Users update own profile"
  on public.profiles for update
  to authenticated
  using (auth.uid() = id);

create policy "Users read own results"
  on public.game_results for select
  to authenticated
  using (auth.uid() = user_id);

create policy "Users insert own results"
  on public.game_results for insert
  to authenticated
  with check (auth.uid() = user_id);
