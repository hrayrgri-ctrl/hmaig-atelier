# HMAIG Services — atelier

Outil de gestion de l'atelier (réparations, SAV magasins, devis et factures, stock) et espace client.

- `index.html` — l'outil de l'atelier (https://atelier.hmaigservices.fr)
- `client/index.html` — la page où les clients envoient leur demande et suivent leur réparation (https://atelier.hmaigservices.fr/client/)
- `supabase/schema.sql` — la base de données des demandes (à exécuter une fois dans Supabase, en remplaçant `%%OWNER_EMAIL%%`)
- `supabase/sync.sql` — la synchronisation des données de l'atelier entre appareils (à exécuter ensuite, même remplacement)
- `.github/workflows/keepalive.yml` — évite la mise en pause de la base gratuite

Aucun secret dans ce dépôt : la clé publique Supabase est faite pour être visible, la sécurité est assurée par les règles de la base.

## Import du stock (.csv)

Dans l'onglet Stock, le bouton « Importer (.csv) » ajoute des pièces à partir d'un fichier. Colonnes reconnues : Référence ; Désignation ; Catégorie ; Quantité ; Seuil ; Achat HT ; Vente HT ; Fournisseur ; Emplacement (séparateur `;`, `,` ou tabulation ; prix avec virgule acceptés). Une référence déjà au stock n'est jamais dupliquée : si le fichier donne des prix (Achat HT, Vente HT), ils sont mis à jour ; la quantité et les autres champs ne changent pas. Si le verrou administrateur est actif, l'import demande son mot de passe.

## E-mails automatiques au client

Quand un dossier créé depuis une demande en ligne change d'étape, le client reçoit un e-mail (s'il a laissé son adresse) avec le lien de suivi. À l'étape « Devis envoyé », son devis part en PDF avec le message ; le bouton « ✉ Envoyer par e-mail » d'un devis permet de le renvoyer.

- L'outil copie le devis dans la colonne `devis` de la demande (voir `supabase/schema.sql`) en même temps que la nouvelle étape.
- Un déclencheur de la base (extension `pg_net`) appelle alors un script Google Apps Script, qui fabrique le PDF et envoie l'e-mail depuis `hmaigservices@gmail.com` (limite Gmail : 100 e-mails par jour).
- Le déclencheur et le script contiennent un code secret : ils ne sont pas dans ce dépôt.

## Synchronisation entre appareils

L'onglet « Compte & synchro » enregistre en ligne les clients, appareils, réparations, SAV, devis, factures, stock, commandes et réglages, pour les retrouver sur n'importe quel ordinateur, téléphone ou navigateur en se connectant avec le compte de l'atelier (le même que pour « Demandes clients »).

- **Fonctionnement** : l'outil garde sa copie locale (il marche donc sans connexion). Environ 2 secondes après chaque modification, il envoie l'ensemble à la table `atelier_donnees` (un seul document) ; il reprend les changements des autres appareils toutes les minutes, au retour sur l'onglet et au retour du réseau.
- **Écriture contrôlée** : l'écriture passe uniquement par la fonction `enregistrer_donnees`, qui vérifie le numéro de version. Si un autre appareil a écrit entre-temps, l'envoi est refusé et l'outil **fusionne** les deux versions fiche par fiche (comparaison avec la dernière version commune) avant de réessayer : une fiche modifiée d'un seul côté est reprise, une fiche modifiée des deux côtés garde la version de l'appareil qui synchronise, une fiche supprimée d'un côté mais modifiée de l'autre est conservée.
- **Première connexion d'un appareil** : appareil vide ou avec l'exemple → il récupère les données en ligne ; données en ligne vides → les siennes sont envoyées ; des données des deux côtés → un choix est proposé (fusionner, garder cet appareil, prendre les données en ligne ; dans ce dernier cas une sauvegarde de l'appareil est téléchargée avant). Les données d'exemple ne sont jamais envoyées sans confirmation.
- **Sauvegardes automatiques** : la table `atelier_historique` conserve les 60 dernières versions (au plus une toutes les 30 minutes, plus une à chaque remplacement volontaire ou baisse brutale du volume de données). L'onglet permet de restaurer l'une d'elles.
- **Sécurité** : les deux tables ne sont lisibles que par le compte de l'atelier (même règle que les demandes) ; personne d'autre, visiteurs compris, ne peut les lire ni les écrire.
- **Hors connexion** : les modifications restent sur l'appareil (marquées « en attente ») et partent dès le retour du réseau.

## Devis : main d'œuvre obligatoire

Chaque devis commence par une ligne « Main d'œuvre » qui ne peut pas être supprimée (son prix reste modifiable). Un avertissement s'affiche tant qu'elle est à 0 €, et une confirmation est demandée avant d'envoyer un tel devis. Les anciens devis en brouillon ou déjà envoyés reçoivent cette ligne à leur ouverture ; les devis acceptés ne sont pas modifiés.

## Verrou administrateur (actuellement désactivé)

Le verrou est **désactivé** : la configuration `ADMIN_EMAIL` est vide, aucun mot de passe n'est demandé. Pour le réactiver, renseigner `ADMIN_EMAIL` (compte Supabase `hmaigservices@gmail.com`) et republier. Lorsqu'il est actif, les actions sensibles demandent le mot de passe du compte `hmaigservices@gmail.com` : suppression d'un client, d'un appareil hors garantie, d'un dossier, d'un devis, d'une facture ou d'une demande en ligne ; création, modification ou suppression de stock ; paramètres de la société et techniciens ; effacement ou restauration des données.

- Le compte est créé une fois dans Supabase : *Authentication → Users → Add user → Create new user* (case « Auto Confirm User » cochée).
- Le mot de passe est vérifié par Supabase Auth, puis la session de vérification est fermée aussitôt : rien n'est mémorisé, le mot de passe est redemandé à chaque action.
- Ce compte n'a aucun droit sur la table des demandes (les règles de la base ne reconnaissent que le compte de l'atelier) : il sert uniquement à confirmer l'identité.
- Sans base configurée (version hors ligne) ou sans `ADMIN_EMAIL`, le verrou est inactif.
