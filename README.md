# HMAIG Services — atelier

Outil de gestion de l'atelier (réparations, SAV magasins, devis et factures, stock) et espace client.

- `index.html` — l'outil de l'atelier (https://atelier.hmaigservices.fr)
- `client/index.html` — la page où les clients envoient leur demande et suivent leur réparation (https://atelier.hmaigservices.fr/client/)
- `supabase/schema.sql` — la base de données des demandes (à exécuter une fois dans Supabase, en remplaçant `%%OWNER_EMAIL%%`)
- `.github/workflows/keepalive.yml` — évite la mise en pause de la base gratuite

Aucun secret dans ce dépôt : la clé publique Supabase est faite pour être visible, la sécurité est assurée par les règles de la base.

## Import du stock (.csv)

Dans l'onglet Stock, le bouton « Importer (.csv) » ajoute des pièces à partir d'un fichier. Colonnes reconnues : Référence ; Désignation ; Catégorie ; Quantité ; Seuil ; Achat HT ; Vente HT ; Fournisseur ; Emplacement (séparateur `;`, `,` ou tabulation ; prix avec virgule acceptés). Une référence déjà au stock n'est jamais modifiée ni dupliquée. L'import demande le mot de passe administrateur.

## Verrou administrateur

Les actions sensibles demandent le mot de passe du compte `hmaigservices@gmail.com` : suppression d'un client, d'un appareil hors garantie, d'un dossier, d'un devis, d'une facture ou d'une demande en ligne ; création, modification ou suppression de stock ; paramètres de la société et techniciens ; effacement ou restauration des données.

- Le compte est créé une fois dans Supabase : *Authentication → Users → Add user → Create new user* (case « Auto Confirm User » cochée).
- Le mot de passe est vérifié par Supabase Auth, puis la session de vérification est fermée aussitôt : rien n'est mémorisé, le mot de passe est redemandé à chaque action.
- Ce compte n'a aucun droit sur la table des demandes (les règles de la base ne reconnaissent que le compte de l'atelier) : il sert uniquement à confirmer l'identité.
- Sans base configurée (version hors ligne), le verrou est inactif.
