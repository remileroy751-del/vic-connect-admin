# VIC-CONNECT — version mise à jour

Projet prêt pour GitHub :
- application Android Kotlin/Jetpack Compose ;
- interface Super Admin statique dans `index.html` et `admin/index.html` ;
- workflow GitHub Actions dans `.github/workflows/android.yml` ;
- migrations Supabase dans `supabase/`.

## Mise à jour Supabase

Après avoir remplacé les fichiers du dépôt GitHub, ouvrir Supabase > SQL Editor et exécuter **le contenu** de :

`supabase/migration-v3.sql`

Ne pas taper le nom du fichier dans SQL Editor.

Cette migration ajoute notamment :
- registre administratif des nouveaux codes parents/enseignants ;
- historique des renouvellements de codes ;
- RPC sécurisée `admin_access_codes` pour la Direction ;
- modification des affectations enseignant/classe/matière via `admin_update_teacher_assignment`.

Les codes créés avant cette migration ne peuvent pas être retrouvés depuis leur hash. Ils apparaîtront dans le registre lors d'une nouvelle création ou d'un renouvellement de code.

## GitHub Pages

La configuration Pages déjà activée peut rester telle quelle (`main` / `/(root)`). Les changements poussés sur `main` sont publiés automatiquement. L'interface Super Admin est disponible à la racine et dans `/admin/`.

## Android

Le workflow compile avec Java 17, Gradle 8.9, Android SDK 35 et publie l'APK Debug comme artefact GitHub Actions.

## Migration Supabase V4
Après déploiement de cette version, exécuter **le contenu complet de `supabase/migration-v4.sql`** dans Supabase > SQL Editor. Cette migration configure la protection de création des classes par mot de passe Direction et conserve uniquement le hash du mot de passe en base.

## Mise à jour V5 — Statistiques et messagerie
Le fichier `supabase/migration-v5-messagerie-statistiques.sql` ajoute les statistiques enseignant, la boîte de réception enseignant et le quota de messagerie de 5 messages par compte et par jour civil GMT.
Exécuter cette migration dans Supabase avant de tester les nouvelles fonctions.
