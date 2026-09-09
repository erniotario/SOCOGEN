# SOCOGEN — Gestion de Stock

Application de gestion de stock pour SOCOGEN (SHEMAB, Yaoundé), écrite en
Flutter et livrée sur **Windows, Android et iOS** depuis une seule base de
code.

En production : environ 400 articles répartis sur trois magasins
(Hysacam, Ekie, Elig-Essono), quelques milliers de mouvements par an,
repris de Sage Gestion Commerciale.

## Démarrage

Le code de l'application est dans `flutter_app/`.

```bash
cd flutter_app
flutter pub get
flutter run -d windows        # ou -d <appareil Android>
```

## Compilation

```bash
cd flutter_app
flutter build windows --release
flutter build apk --release
```

L'installateur Windows se compile avec Inno Setup, **en dehors du dossier
du projet** — l'antivirus interrompt une compilation faite sur place :

```bash
ISCC.exe "/O<dossier-temporaire>" installer.iss
```

puis copier `SOCOGEN_Setup.exe` dans `flutter_app/dist/`.

## Fonctionnalités

| Page | Description |
|---|---|
| **Tableau de bord** | Indicateurs clés et stock actuel par produit |
| **Produits** | Catalogue, recherche, stock d'ouverture par magasin, import Excel |
| **Entrées** | Réceptions : date, fournisseur, magasin, quantité |
| **Sorties** | Sorties : date, facture, destination, magasin, quantité |
| **Transactions** | Historique des mouvements avec le stock après chaque opération, export et impression PDF |
| **Rapports** | État des stocks par produit et par magasin |
| **Magasins** | Gestion des magasins |
| **Sécurité** | Comptes et rôles, import d'une base, synchronisation Wi-Fi entre appareils |
| **Paramètres** | Informations de l'entreprise reprises dans les rapports |

Sur Android, les listes sont volontairement réduites à ce qui se lit dans
une allée : produit, magasin, stock actuel. Les postes de bureau gardent
le détail complet.

## Base de données

SQLite, un fichier par appareil, créé au premier lancement à partir de la
base fournie dans `assets/db/socogen_seed.db`.

| Plateforme | Emplacement |
|---|---|
| Windows | à côté de l'exécutable |
| Android / iOS | dossier documents de l'application (`app_flutter/socogen_stock.db`) |

Le stock actuel n'est jamais stocké : il vaut
`stock initial + entrées − sorties`. La colonne `initial_stock` contient
donc le stock **d'ouverture**, pas le stock du jour.

## Import depuis Sage

Un classeur Excel dont les feuilles s'appellent *Produits*, *Entrées* et
*Sorties* s'importe depuis la page Produits. Réimporter le même fichier
n'ajoute rien.

`scripts/gcm_to_excel.py` lit directement un fichier `.gcm` de Sage
Gestion Commerciale et en extrait le catalogue des articles :

```bash
.venv/Scripts/python.exe scripts/gcm_to_excel.py GESCOM_SOCOGEN_2025.gcm
```

Le stock par dépôt et les dates de mouvement n'ont pas pu être décodés de
façon fiable dans ce format : ces colonnes sont laissées vides plutôt que
devinées. Pour les reprendre, exporter depuis Sage lui-même.

## Structure

```
flutter_app/        l'application
  lib/screens/      les pages
  lib/data/         base de données, modèles, repositories
  lib/services/     PDF, import Excel, synchronisation Wi-Fi
  lib/widgets/      composants partagés (dont AdaptiveTable)
  test/             ~125 tests
scripts/            outillage Python (base seed, lecteur Sage .gcm)
CLAUDE.md           notes de développement et règles du domaine
```

Une version antérieure de cette application, écrite en Python/PySide6, a
été retirée du dépôt ; elle reste consultable dans l'historique Git.
