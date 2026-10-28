-- ============================================================
-- HMAIG Services — synchronisation des données de l'atelier entre appareils
-- À exécuter une fois dans Supabase (SQL Editor), APRÈS schema.sql.
-- Remplacer %%OWNER_EMAIL%% par l'adresse e-mail du compte atelier (la même que pour schema.sql).
-- Relançable sans risque (rien n'est supprimé).
-- ============================================================

-- Qui est le compte atelier ?
create or replace function public.est_atelier() returns boolean
language sql stable as $$
  select lower(coalesce(auth.jwt() ->> 'email', '')) = lower('%%OWNER_EMAIL%%')
$$;
revoke all on function public.est_atelier() from public;
grant execute on function public.est_atelier() to authenticated;

-- Les données de l'atelier : UN seul document (clients, dossiers, stock, devis, factures, réglages…).
create table if not exists public.atelier_donnees (
  id          int primary key default 1 check (id = 1),
  contenu     jsonb       not null,
  version     bigint      not null default 1,
  modifie_le  timestamptz not null default now(),
  modifie_par text
);

-- Sauvegardes automatiques (versions précédentes) pour pouvoir revenir en arrière.
create table if not exists public.atelier_historique (
  id        bigserial primary key,
  version   bigint      not null,
  cree_le   timestamptz not null default now(),
  appareil  text,
  resume    jsonb       not null default '{}'::jsonb,
  contenu   jsonb       not null
);
create index if not exists atelier_historique_date_idx on public.atelier_historique (cree_le desc);

alter table public.atelier_donnees   enable row level security;
alter table public.atelier_historique enable row level security;
revoke all on public.atelier_donnees, public.atelier_historique from anon, authenticated;

-- Lecture réservée au compte atelier ; l'écriture ne passe que par la fonction ci-dessous.
grant select on public.atelier_donnees, public.atelier_historique to authenticated;
drop policy if exists atelier_lit_donnees on public.atelier_donnees;
create policy atelier_lit_donnees on public.atelier_donnees
  for select to authenticated using (public.est_atelier());
drop policy if exists atelier_lit_historique on public.atelier_historique;
create policy atelier_lit_historique on public.atelier_historique
  for select to authenticated using (public.est_atelier());
grant usage, select on sequence public.atelier_historique_id_seq to authenticated;

-- Enregistrement avec contrôle de version : si un autre appareil a écrit entre-temps,
-- la fonction refuse (ok = false) et renvoie la version en ligne ; l'outil fusionne puis réessaie.
create or replace function public.enregistrer_donnees(
  p_contenu           jsonb,
  p_version_attendue  bigint,
  p_appareil          text    default null,
  p_sauvegarde        boolean default false
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  cur      public.atelier_donnees%rowtype;
  nouvelle bigint;
  derniere timestamptz;
  taille_a bigint;
  taille_n bigint;
begin
  if not public.est_atelier() then
    raise exception 'Compte non autorisé' using errcode = '42501';
  end if;
  if p_contenu is null or jsonb_typeof(p_contenu) <> 'object' then
    raise exception 'Données invalides' using errcode = '22023';
  end if;
  if octet_length(p_contenu::text) > 30000000 then
    raise exception 'Données trop volumineuses' using errcode = '54000';
  end if;

  select * into cur from public.atelier_donnees where id = 1 for update;

  if not found then
    if p_version_attendue <> 0 then
      return jsonb_build_object('ok', false, 'version', 0);
    end if;
    insert into public.atelier_donnees (id, contenu, version, modifie_par)
      values (1, p_contenu, 1, p_appareil);
    return jsonb_build_object('ok', true, 'version', 1);
  end if;

  if cur.version <> p_version_attendue then
    return jsonb_build_object('ok', false, 'version', cur.version, 'modifie_le', cur.modifie_le, 'modifie_par', cur.modifie_par);
  end if;

  -- Sauvegarde de l'ancienne version : demandée, ou la dernière date de plus de 30 min,
  -- ou les données rétrécissent nettement (suppression massive / effacement).
  select max(cree_le) into derniere from public.atelier_historique;
  taille_a := octet_length(cur.contenu::text);
  taille_n := octet_length(p_contenu::text);
  if p_sauvegarde or derniere is null or derniere < now() - interval '30 minutes'
     or taille_n < taille_a * 0.6 then
    insert into public.atelier_historique (version, appareil, resume, contenu)
    values (cur.version, cur.modifie_par,
            jsonb_build_object(
              'dossiers', coalesce(jsonb_array_length(cur.contenu -> 'repairs'), 0),
              'clients',  coalesce(jsonb_array_length(cur.contenu -> 'clients'), 0),
              'pieces',   coalesce(jsonb_array_length(cur.contenu -> 'parts'), 0),
              'documents',coalesce(jsonb_array_length(cur.contenu -> 'docs'), 0)),
            cur.contenu);
    -- on garde les 60 dernières sauvegardes
    delete from public.atelier_historique
     where id not in (select id from public.atelier_historique order by id desc limit 60);
  end if;

  update public.atelier_donnees
     set contenu = p_contenu, version = cur.version + 1, modifie_le = now(), modifie_par = p_appareil
   where id = 1
   returning version into nouvelle;
  return jsonb_build_object('ok', true, 'version', nouvelle);
end $$;
revoke all on function public.enregistrer_donnees(jsonb, bigint, text, boolean) from public, anon;
grant execute on function public.enregistrer_donnees(jsonb, bigint, text, boolean) to authenticated;
