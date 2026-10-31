-- HMAIG Services : compte rendu d'intervention visible dans l'espace magasin.
-- À exécuter une seule fois dans Supabase > SQL Editor (après stores.sql). Peut être relancé sans risque.
-- Ajoute deux cases à chaque SAV publié : « travaux » (texte écrit pour le magasin) et « pieces » (noms des pièces, sans prix).

alter table public.sav_magasin add column if not exists travaux text;
alter table public.sav_magasin add column if not exists pieces text;
do $$ begin
  alter table public.sav_magasin add constraint sav_magasin_travaux_taille check (travaux is null or char_length(travaux) <= 1000);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.sav_magasin add constraint sav_magasin_pieces_taille check (pieces is null or char_length(pieces) <= 300);
exception when duplicate_object then null; end $$;

-- La liste renvoyée change de forme : on remplace la fonction.
drop function if exists public.mes_reparations();
create or replace function public.mes_reparations()
returns table (origine text, ref text, code text, appareil text, serie text, panne text, statut text,
               message text, decision text, info text, recu_le timestamptz, maj_le timestamptz,
               travaux text, pieces text)
language sql stable security definer set search_path = public as $$
  select 'demande'::text, coalesce(d.repair_ref, d.code), d.code, d.model, d.serial, d.issue,
         d.public_status, d.public_message, null::text, null::text, d.created_at, d.updated_at,
         null::text, null::text
    from public.demandes d
   where auth.uid() is not null and d.user_id = auth.uid()
  union all
  select 'atelier'::text, s.ref, null::text, s.appareil, s.serie, s.panne,
         s.statut, null::text, s.decision, s.info, s.recu_le::timestamptz, s.maj_le,
         s.travaux, s.pieces
    from public.sav_magasin s
   where auth.uid() is not null and s.user_id = auth.uid()
  order by 11 desc nulls last
$$;
revoke all on function public.mes_reparations() from public, anon;
grant execute on function public.mes_reparations() to authenticated;

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

  insert into public.sav_magasin (user_id, ref, appareil, serie, panne, statut, decision, info, travaux, pieces, recu_le)
  select p_user, left(btrim(x ->> 'ref'), 40), left(coalesce(x ->> 'appareil', ''), 120),
         nullif(left(coalesce(x ->> 'serie', ''), 60), ''), nullif(left(coalesce(x ->> 'panne', ''), 2000), ''),
         x ->> 'statut', nullif(left(coalesce(x ->> 'decision', ''), 200), ''), nullif(left(coalesce(x ->> 'info', ''), 500), ''),
         nullif(left(coalesce(x ->> 'travaux', ''), 1000), ''), nullif(left(coalesce(x ->> 'pieces', ''), 300), ''),
         nullif(x ->> 'recu_le', '')::date
    from jsonb_array_elements(p_items) x
  on conflict (user_id, ref) do update
     set appareil = excluded.appareil, serie = excluded.serie, panne = excluded.panne, statut = excluded.statut,
         decision = excluded.decision, info = excluded.info, travaux = excluded.travaux, pieces = excluded.pieces,
         recu_le = excluded.recu_le, maj_le = now()
   where (public.sav_magasin.appareil, public.sav_magasin.serie, public.sav_magasin.panne, public.sav_magasin.statut,
          public.sav_magasin.decision, public.sav_magasin.info, public.sav_magasin.travaux, public.sav_magasin.pieces,
          public.sav_magasin.recu_le)
         is distinct from
         (excluded.appareil, excluded.serie, excluded.panne, excluded.statut, excluded.decision, excluded.info,
          excluded.travaux, excluded.pieces, excluded.recu_le);

  delete from public.sav_magasin s
   where s.user_id = p_user
     and s.ref not in (select left(btrim(x ->> 'ref'), 40) from jsonb_array_elements(p_items) x);

  return jsonb_build_object('ok', true, 'n', jsonb_array_length(p_items));
end $$;
revoke all on function public.synchroniser_sav_magasin(uuid, jsonb) from public, anon;
grant execute on function public.synchroniser_sav_magasin(uuid, jsonb) to authenticated;
