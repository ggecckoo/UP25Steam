-- Çok oyunculu masalar (multiplayer tables)
--
-- A table is a lobby until its host starts it, then a sitting played by up
-- to four people (bots fill empty seats). The `game-table` edge function is
-- the only writer: it checks every move with the shared rules engine and
-- commits through `game_table_commit`. Players only read, over Realtime:
--   game_tables         public state of the tables they sit at
--   game_table_members  who sits where at those tables
--   game_table_hands    their own cards, and no one else's
-- The full engine (deck, everyone's cards, the random state) lives in
-- game_table_engines, which no client can read.

create table if not exists public.game_tables (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z0-9]{6}$'),
  host uuid not null references auth.users (id) on delete cascade,
  status text not null default 'lobby' check (status in ('lobby', 'playing', 'over', 'closed')),
  seats jsonb not null default '[]'::jsonb,
  state jsonb not null default '{}'::jsonb,
  version int not null default 0,
  deadline timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists game_tables_status_deadline_idx
  on public.game_tables (status, deadline);

create table if not exists public.game_table_members (
  table_id uuid not null references public.game_tables (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  seat int not null check (seat between 0 and 3),
  display_name text not null default '',
  preset text not null default '',
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  primary key (table_id, user_id),
  unique (table_id, seat)
);

create index if not exists game_table_members_user_idx
  on public.game_table_members (user_id);

create table if not exists public.game_table_hands (
  table_id uuid not null references public.game_tables (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  seat int not null check (seat between 0 and 3),
  cards jsonb not null default '[]'::jsonb,
  version int not null default 0,
  primary key (table_id, user_id)
);

create table if not exists public.game_table_engines (
  table_id uuid primary key references public.game_tables (id) on delete cascade,
  engine jsonb not null,
  version int not null default 0
);

drop trigger if exists game_tables_updated_at on public.game_tables;
create trigger game_tables_updated_at
  before update on public.game_tables
  for each row execute function public.set_updated_at();

-- --- who may read what ----------------------------------------------------------

-- Membership checked outside RLS, so the members policy does not recurse.
create or replace function public.is_game_table_member(p_table uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.game_table_members m
    where m.table_id = p_table and m.user_id = auth.uid()
  );
$$;

revoke all on function public.is_game_table_member(uuid) from public;
grant execute on function public.is_game_table_member(uuid) to authenticated;

alter table public.game_tables enable row level security;
alter table public.game_table_members enable row level security;
alter table public.game_table_hands enable row level security;
alter table public.game_table_engines enable row level security;

drop policy if exists "Members read their tables" on public.game_tables;
create policy "Members read their tables"
  on public.game_tables for select
  to authenticated
  using (public.is_game_table_member(id));

drop policy if exists "Members read their table's seats" on public.game_table_members;
create policy "Members read their table's seats"
  on public.game_table_members for select
  to authenticated
  using (public.is_game_table_member(table_id));

drop policy if exists "Players read their own hand" on public.game_table_hands;
create policy "Players read their own hand"
  on public.game_table_hands for select
  to authenticated
  using (user_id = auth.uid());

-- game_table_engines: no policies at all, so only the service role reads it.
-- No insert/update/delete policies anywhere: clients never write directly.

-- --- the one way a table changes ------------------------------------------------

create or replace function public.game_table_commit(
  p_table uuid,
  p_expected int,
  p_status text,
  p_seats jsonb,
  p_state jsonb,
  p_deadline timestamptz,
  p_engine jsonb,
  p_hands jsonb,
  p_results jsonb
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_version int;
begin
  -- Only if no one committed since the caller read the table.
  update public.game_tables
     set status = p_status,
         seats = coalesce(p_seats, seats),
         state = coalesce(p_state, '{}'::jsonb),
         deadline = p_deadline,
         version = version + 1
   where id = p_table
     and version = p_expected
  returning version into v_version;

  if v_version is null then
    return -1;
  end if;

  if p_engine is not null and p_engine <> 'null'::jsonb then
    insert into public.game_table_engines (table_id, engine, version)
    values (p_table, p_engine, v_version)
    on conflict (table_id) do update
      set engine = excluded.engine,
          version = excluded.version;
  end if;

  insert into public.game_table_hands (table_id, user_id, seat, cards, version)
  select p_table,
         (h ->> 'user_id')::uuid,
         (h ->> 'seat')::int,
         coalesce(h -> 'cards', '[]'::jsonb),
         v_version
    from jsonb_array_elements(coalesce(p_hands, '[]'::jsonb)) as h
  on conflict (table_id, user_id) do update
    set seat = excluded.seat,
        cards = excluded.cards,
        version = excluded.version;

  -- A finished sitting counts in each player's record, once (the engine
  -- marks itself recorded in this same commit).
  insert into public.game_results (user_id, score, placement, won)
  select (r ->> 'user_id')::uuid,
         (r ->> 'score')::int,
         (r ->> 'placement')::int,
         coalesce((r ->> 'won')::boolean, false)
    from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) as r
   where exists (select 1 from public.profiles p where p.id = (r ->> 'user_id')::uuid);

  update public.profiles p
     set games_played = p.games_played + 1,
         games_won = p.games_won + case when coalesce((r ->> 'won')::boolean, false) then 1 else 0 end
    from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) as r
   where p.id = (r ->> 'user_id')::uuid;

  return v_version;
end;
$$;

revoke all on function public.game_table_commit(uuid, int, text, jsonb, jsonb, timestamptz, jsonb, jsonb, jsonb) from public;
revoke all on function public.game_table_commit(uuid, int, text, jsonb, jsonb, timestamptz, jsonb, jsonb, jsonb) from anon, authenticated;
grant execute on function public.game_table_commit(uuid, int, text, jsonb, jsonb, timestamptz, jsonb, jsonb, jsonb) to service_role;

-- --- live updates ------------------------------------------------------------------

do $$
declare
  v_table text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach v_table in array array['game_tables', 'game_table_members', 'game_table_hands'] loop
      if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = v_table
      ) then
        execute format('alter publication supabase_realtime add table public.%I', v_table);
      end if;
    end loop;
  end if;
end;
$$;
