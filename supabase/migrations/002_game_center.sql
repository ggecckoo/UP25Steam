-- Game Center kimliği için profil alanı
alter table public.profiles
  add column if not exists game_center_id text;

create unique index if not exists profiles_game_center_id_uidx
  on public.profiles (game_center_id)
  where game_center_id is not null;
