# HMAIG Services — atelier

Outil de gestion de l'atelier (réparations, SAV magasins, devis et factures, stock) et espace client.

- `index.html` — l'outil de l'atelier (https://atelier.hmaigservices.fr)
- `client/index.html` — la page où les clients envoient leur demande et suivent leur réparation (https://atelier.hmaigservices.fr/client/)
- `supabase/schema.sql` — la base de données des demandes (à exécuter une fois dans Supabase, en remplaçant `%%OWNER_EMAIL%%`)
- `.github/workflows/keepalive.yml` — évite la mise en pause de la base gratuite

Aucun secret dans ce dépôt : la clé publique Supabase est faite pour être visible, la sécurité est assurée par les règles de la base.
