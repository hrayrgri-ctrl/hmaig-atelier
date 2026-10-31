-- ============================================================
-- HMAIG Services — comptes des magasins partenaires
-- À exécuter une fois dans Supabase (SQL Editor), APRÈS schema.sql et sync.sql.
-- Rien n'est supprimé : peut être relancé sans risque.
--
-- Principe : chaque magasin crée son compte (e-mail + mot de passe) depuis la page client.
-- Il ne lit JAMAIS les tables directement : il passe par des fonctions qui ne renvoient que
-- ses propres lignes et seulement les colonnes publiques (jamais les notes internes ni les devis).
-- Le compte atelier relie ensuite le compte à la fiche du magasin dans l'outil.
-- ============================================================

-- 1) Les demandes envoyées depuis un compte magasin portent l'identifiant du compte.
alter table public.demandes add column if not exists user_id uuid references auth.users(id) on delete set null;
create index if not exists demandes_user_idx on public.demandes (user_id) where user_id is not null;

-- 2) Profil du magasin (créé automatiquement à l'inscription).
create table if not exists public.magasins (
  user_id   uuid primary key references auth.users(id) on delete cascade,
  nom       text not null check (char_length(nom) between 2 and 120),
  contact   text not null check (char_length(contact) between 2 and 120),
  telephone text not null check (char_length(telephone) between 6 and 30),
  email     text,
  cree_le   timestamptz not null default now()
);
alter table public.magasins enable row level security;
revoke all on public.magasins from anon, authenticated;
grant select on public.magasins to authenticated;
drop policy if exists magasins_lecture on public.magasins;
create policy magasins_lecture on public.magasins
  for select to authenticated using (user_id = auth.uid() or public.est_atelier());

create or replace function public.nouveau_compte() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(new.raw_user_meta_data ->> 'type', '') = 'magasin' then
    insert into public.magasins (user_id, nom, contact, telephone, email)
    values (new.id,
            left(btrim(coalesce(new.raw_user_meta_data ->> 'nom', '')), 120),
            left(btrim(coalesce(new.raw_user_meta_data ->> 'contact', '')), 120),
            left(btrim(coalesce(new.raw_user_meta_data ->> 'telephone', '')), 30),
            new.email);
  end if;
  return new;
end $$;
revoke all on function public.nouveau_compte() from public, anon, authenticated;
drop trigger if exists compte_magasin_cree on auth.users;
create trigger compte_magasin_cree after insert on auth.users
  for each row execute function public.nouveau_compte();

-- 3) Copie, côté magasin, des SAV que l'atelier enregistre pour lui (publiée par l'outil de l'atelier).
create table if not exists public.sav_magasin (
  id       uuid primary key default gen_random_uuid(),
  user_id  uuid not null references auth.users(id) on delete cascade,
  ref      text not null check (char_length(ref) between 1 and 40),
  appareil text not null check (char_length(appareil) <= 120),
  serie    text check (serie is null or char_length(serie) <= 60),
  panne    text check (panne is null or char_length(panne) <= 2000),
  statut   text not null check (statut in ('recue','deposee','diagnostic','devis','validee','piece','reparation','controle','prete','terminee','refusee')),
  decision text check (decision is null or char_length(decision) <= 200),
  info     text check (info is null or char_length(info) <= 500),
  recu_le  date,
  maj_le   timestamptz not null default now(),
  unique (user_id, ref)
);
alter table public.sav_magasin enable row level security;
revoke all on public.sav_magasin from anon, authenticated;   -- aucun accès direct : uniquement les fonctions ci-dessous

-- 4) Ce que voit un magasin : ses demandes en ligne + les SAV que l'atelier a saisis pour lui.
create or replace function public.mes_reparations()
returns table (origine text, ref text, code text, appareil text, serie text, panne text, statut text,
               message text, decision text, info text, recu_le timestamptz, maj_le timestamptz)
language sql stable security definer set search_path = public as $$
  select 'demande'::text, coalesce(d.repair_ref, d.code), d.code, d.model, d.serial, d.issue,
         d.public_status, d.public_message, null::text, null::text, d.created_at, d.updated_at
    from public.demandes d
   where auth.uid() is not null and d.user_id = auth.uid()
  union all
  select 'atelier'::text, s.ref, null::text, s.appareil, s.serie, s.panne,
         s.statut, null::text, s.decision, s.info, s.recu_le::timestamptz, s.maj_le
    from public.sav_magasin s
   where auth.uid() is not null and s.user_id = auth.uid()
  order by 11 desc nulls last
$$;
revoke all on function public.mes_reparations() from public, anon;
grant execute on function public.mes_reparations() to authenticated;

-- 5) Envoi d'une demande de SAV depuis un compte magasin (le nom du magasin vient du profil, pas du formulaire).
create or replace function public.deposer_demande_magasin(
  p_code text, p_name text, p_phone text, p_email text, p_device_type text,
  p_model text, p_serial text, p_sale_date date, p_issue text
) returns text
language plpgsql security definer set search_path = public as $$
declare
  m public.magasins%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Connexion requise' using errcode = '42501';
  end if;
  select * into m from public.magasins where user_id = auth.uid();
  if not found then
    raise exception 'Ce compte n''est pas un compte magasin' using errcode = '42501';
  end if;
  insert into public.demandes (code, kind, name, phone, email, store, device_type, model, serial, sale_date, issue, consent, user_id)
  values (upper(btrim(p_code)), 'sav', btrim(p_name), btrim(p_phone), nullif(btrim(coalesce(p_email, '')), ''), m.nom,
          nullif(btrim(coalesce(p_device_type, '')), ''), btrim(p_model), nullif(btrim(coalesce(p_serial, '')), ''),
          p_sale_date, btrim(p_issue), true, auth.uid());
  return upper(btrim(p_code));
end $$;
revoke all on function public.deposer_demande_magasin(text, text, text, text, text, text, text, date, text) from public, anon;
grant execute on function public.deposer_demande_magasin(text, text, text, text, text, text, text, date, text) to authenticated;

-- 6) Publication par l'atelier : remplace l'ensemble des SAV affichés pour un magasin.
create or replace function public.synchroniser_sav_magasin(p_user uuid, p_items jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.est_atelier() then
    raise exception 'Compte non autorisé' using errcode = '42501';
  end if;
  if not exists (select 1 from public.magasins where user_id = p_user) then
    raise exception 'Compte magasin inconnu' using errcode = '22023';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) > 3000 then
    raise exception 'Données invalides' using errcode = '22023';
  end if;

  insert into public.sav_magasin (user_id, ref, appareil, serie, panne, statut, decision, info, recu_le)
  select p_user, left(btrim(x ->> 'ref'), 40), left(coalesce(x ->> 'appareil', ''), 120),
         nullif(left(coalesce(x ->> 'serie', ''), 60), ''), nullif(left(coalesce(x ->> 'panne', ''), 2000), ''),
         x ->> 'statut', nullif(left(coalesce(x ->> 'decision', ''), 200), ''), nullif(left(coalesce(x ->> 'info', ''), 500), ''),
         nullif(x ->> 'recu_le', '')::date
    from jsonb_array_elements(p_items) x
  on conflict (user_id, ref) do update
     set appareil = excluded.appareil, serie = excluded.serie, panne = excluded.panne, statut = excluded.statut,
         decision = excluded.decision, info = excluded.info, recu_le = excluded.recu_le, maj_le = now()
   where (public.sav_magasin.appareil, public.sav_magasin.serie, public.sav_magasin.panne, public.sav_magasin.statut,
          public.sav_magasin.decision, public.sav_magasin.info, public.sav_magasin.recu_le)
         is distinct from
         (excluded.appareil, excluded.serie, excluded.panne, excluded.statut, excluded.decision, excluded.info, excluded.recu_le);

  delete from public.sav_magasin s
   where s.user_id = p_user
     and s.ref not in (select left(btrim(x ->> 'ref'), 40) from jsonb_array_elements(p_items) x);

  return jsonb_build_object('ok', true, 'n', jsonb_array_length(p_items));
end $$;
revoke all on function public.synchroniser_sav_magasin(uuid, jsonb) from public, anon;
grant execute on function public.synchroniser_sav_magasin(uuid, jsonb) to authenticated;
