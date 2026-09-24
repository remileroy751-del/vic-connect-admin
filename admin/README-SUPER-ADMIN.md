# VIC-CONNECT — Super Admin Web

Interface web de gestion complète de VIC-CONNECT.

## Connexion
- Utiliser un compte Supabase Auth avec email + mot de passe.
- Si c'est la première utilisation, cliquer sur « INITIALISER CE COMPTE SUPER ADMIN ».
- Le compte est ajouté dans `public.admin_users` via `bootstrap_admin`.

## Déploiement GitHub Pages
1. Créer un dépôt GitHub.
2. Mettre `admin/index.html` à la racine du dépôt (ou utiliser le dossier `admin` comme source selon votre configuration).
3. Activer GitHub Pages.
4. Ouvrir l'adresse Pages fournie par GitHub.

La clé Publishable Supabase est prévue pour être utilisée côté navigateur. Ne jamais mettre une clé `service_role` dans ce fichier.

## Modules
- Tableau de bord
- Élèves & parents
- Codes parents 4 caractères
- Enseignants
- Codes enseignants 5 caractères
- Classes et matières
- Affectations enseignant/classe/matière
- Notes
- Envoyer un message (À tous les parents / Aux parents d'une classe / À tous les enseignants / À un enseignant — Urgent ou Pas urgent)
- Accusés de réception
- Messagerie interne
- Administration Super Admin
