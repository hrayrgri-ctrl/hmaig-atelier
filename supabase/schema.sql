-- HMAIG Services : demandes clients (Supabase / PostgreSQL)
-- À exécuter une seule fois dans « SQL Editor ». Peut être relancé sans risque.
-- Remplacer %%OWNER_EMAIL%% par l'adresse e-mail du compte atelier avant exécution.

create table if not exists public.demandes (
  id             uuid primary key default gen_random_uuid(),
  code           text not null unique
                 check (code ~ '^HM-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$'),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  kind           text not null check (kind in ('reparation','sav')),
  status         text not null default 'nouvelle'
                 check (status in ('nouvelle','vue','convertie','refusee')),
  public_status  text not null default 'recue'
                 check (public_status in ('recue','deposee','diagnostic','devis','validee','piece','reparation','controle','prete','terminee','refusee')),
  public_message text check (public_message is null or char_length(public_message) <= 500),
  name           text not null check (char_length(name) between 2 and 120),
  phone          text not null check (char_length(phone) between 6 and 30),
  email          text check (email is null or char_length(email) <= 160),
  store          text check (store is null or char_length(store) <= 120),
  device_type    text check (device_type is null or char_length(device_type) <= 40),
  model          text not null check (char_length(model) between 2 and 120),
  serial         text check (serial is null or char_length(serial) <= 60),
  sale_date      date,
  issue          text not null check (char_length(issue) between 5 and 2000),
  consent        boolean not null check (consent),
  owner_note     text check (owner_note is null or char_length(owner_note) <= 2000),
  repair_ref     text check (repair_ref is null or char_length(repair_ref) <= 40),
  check (kind <> 'sav' or (store is not null and char_length(store) >= 2))
);

create index if not exists demandes_created_idx on public.demandes (created_at desc);

create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists demandes_touch on public.demandes;
create trigger demandes_touch before update on public.demandes
  for each row execute function public.touch_updated_at();
revoke all on function public.touch_updated_at() from public, anon, authenticated;

-- Garde-fou anti-spam : au plus 30 demandes par tranche de 10 minutes (tous visiteurs confondus).
create or replace function public.limite_envois() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.demandes where created_at > now() - interval '10 minutes') >= 30 then
    raise exception 'Trop de demandes en peu de temps : réessayez dans quelques minutes.';
  end if;
  return new;
end $$;
revoke all on function public.limite_envois() from public, anon, authenticated;
drop trigger if exists demandes_limite on public.demandes;
create trigger demandes_limite before insert on public.demandes
  for each row execute function public.limite_envois();

-- Sécurité : personne ne lit rien sans être connecté, sauf le suivi par code.
alter table public.demandes enable row level security;
revoke all on public.demandes from anon, authenticated;

-- Les visiteurs peuvent seulement DÉPOSER une demande (ces colonnes uniquement).
grant insert (code, kind, name, phone, email, store, device_type, model, serial, sale_date, issue, consent)
  on public.demandes to anon;
drop policy if exists clients_envoi on public.demandes;
create policy clients_envoi on public.demandes
  for insert to anon with check (true);

-- Le compte atelier (et lui seul) peut tout lire, modifier, supprimer.
grant select, update, delete on public.demandes to authenticated;
drop policy if exists atelier_tout on public.demandes;
create policy atelier_tout on public.demandes
  for all to authenticated
  using (lower(auth.jwt() ->> 'email') = lower('%%OWNER_EMAIL%%'))
  with check (lower(auth.jwt() ->> 'email') = lower('%%OWNER_EMAIL%%'));

-- Suivi côté client : on ne retrouve une demande que si l'on connaît son code exact.
create or replace function public.suivi_demande(p_code text)
returns table (kind text, model text, created_at timestamptz, updated_at timestamptz,
               public_status text, public_message text)
language sql stable security definer set search_path = public as $$
  select d.kind, d.model, d.created_at, d.updated_at, d.public_status, d.public_message
  from public.demandes d
  where d.code = upper(btrim(p_code))
  limit 1
$$;
revoke all on function public.suivi_demande(text) from public;
grant execute on function public.suivi_demande(text) to anon, authenticated;

-- Petit signal de vie (garde le projet gratuit actif).
create or replace function public.ping() returns text
language sql stable as $$ select 'ok'::text $$;
revoke all on function public.ping() from public;
grant execute on function public.ping() to anon, authenticated;
