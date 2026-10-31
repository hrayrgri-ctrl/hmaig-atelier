-- HMAIG Services : plus d'e-mail automatique de suivi pour les magasins.
-- Les magasins suivent leurs SAV dans leur espace en ligne ; seuls les particuliers
-- (demandes de réparation) reçoivent les e-mails de changement d'étape et de devis.
--
-- À exécuter une seule fois dans Supabase > SQL Editor. Peut être relancé sans risque.
-- Sans effet si l'envoi d'e-mails (fonction prevenir_client) n'a jamais été installé.
-- Il suffit de relancer le script d'installation des e-mails pour rétablir l'envoi aux magasins.

do $$
declare
  d text;
begin
  if to_regprocedure('public.prevenir_client()') is null then
    return;
  end if;
  d := pg_get_functiondef('public.prevenir_client()'::regprocedure);
  if position('new.kind = ''sav''' in d) > 0 then
    return;  -- déjà en place
  end if;
  d := replace(d, 'if new.email is null',
               'if new.kind = ''sav'' then return new; end if;' || chr(10) || '  if new.email is null');
  if position('new.kind = ''sav''' in d) = 0 then
    raise exception 'Modification impossible : la fonction prevenir_client a une forme inattendue';
  end if;
  execute d;
end $$;
