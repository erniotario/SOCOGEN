# SOCOGEN — Stock Manager v2.2

Application de gestion de stock pour SOCOGEN avec interface Qt professionnelle.

## Installation

```bash
pip install -r requirements.txt
```

## Démarrage

```bash
python main.py
```

Si `PySide6` est installé, l'application démarrera en mode Qt. Sinon, elle basculera automatiquement vers l'interface `CustomTkinter`.

> La base de données se crée automatiquement au premier lancement. Les magasins par défaut
> (Hysacam, Ekie, Elig-Essono) sont initialisés automatiquement.

## Fonctionnalités

| Page | Description |
|---|---|
| **Tableau de bord** | Vue d'ensemble avec indicateurs clés et stock actuel par produit |
| **Produits** | Ajouter, rechercher et supprimer des produits avec magasin de rattachement |
| **Entrées** | Enregistrer les réceptions de stock avec date, fournisseur et quantité |
| **Sorties** | Enregistrer les sorties de stock avec facture, destination et quantités |
| **Rapports** | Générer des rapports PDF et imprimer des informations d'activité |
| **Transactions** | Suivre l'historique des mouvements de stock |
| **Paramètres** | Configurer les informations de l'entreprise et le logo utilisées dans les rapports |

## Structure du projet

```
./
├── main.py
├── qt_main.py
├── customtkinter_main.py
├── database.py
├── init_db.py
├── reset_db.py
├── models.py
├── styles.py
├── requirements.txt
└── ui/
    ├── dashboard_page.py
    ├── entries_page.py
    ├── inputs_page.py
    ├── outputs_page.py
    ├── products_page.py
    ├── reports_page.py
    ├── settings_page.py
    ├── transactions_page.py
    └── utils.py
```
