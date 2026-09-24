# VIC-CONNECT V8 — Notifications fiables, session permanente, onglet « Envoyer un message »

## Interface Direction (web)
- L'onglet **Communiqués** s'appelle désormais **Envoyer un message** (`index.html` ET `admin/index.html` sont identiques :
  GitHub Pages sert la racine, l'ancienne version de la racine n'avait pas été mise à jour).
- Destinataires : **À tous les parents**, **Aux parents d'une classe**, **À tous les enseignants**, **À un enseignant**.
- Importance : **Urgent** / **Pas urgent**.

## Application Android (parents et enseignants)
- **Vraie notification système** (bannière en haut de l'écran, son, vibration, écran verrouillé) dès qu'un message arrive :
  message de la Direction, d'un parent ou d'un enseignant.
- La surveillance continue **application fermée ou en arrière-plan** (service de premier plan) et
  **redémarre automatiquement après un redémarrage du téléphone** ou une mise à jour de l'application.
- Au premier lancement après connexion, l'application guide l'utilisateur pour :
  1. autoriser les notifications ;
  2. autoriser le fonctionnement en arrière-plan (sans restriction de batterie).
- **Session permanente** : après la première connexion, la réouverture ouvre directement l'espace parent/enseignant.
  Le code n'est redemandé que si l'utilisateur appuie sur **Déconnexion** (ou si la Direction supprime/renouvelle son code).
  Le bouton « Retour » de l'écran d'accueil ne déconnecte plus l'enseignant : il met simplement l'application en arrière-plan.
- Les messages affichés à l'écran (conversations, messages de la Direction) se mettent à jour automatiquement.
- Anti-doublons, heure de référence fournie par le serveur, pas de message manqué.
- Clé de signature fixe (`app/debug.keystore`) : les prochains APK se mettent à jour par-dessus la version installée.
  ⚠ Le tout premier APK V8 nécessite de **désinstaller l'ancienne version** une fois (signature différente).

## Supabase
Exécuter **une seule fois** le contenu de `supabase/migration-v8-notifications-fiables.sql`
(après V6 et V7 déjà exécutées). Sans risque si exécuté plusieurs fois.

## Déploiement
1. Remplacer les fichiers du dépôt GitHub par ceux de ce zip (branche `main`).
2. GitHub Pages (`main` / racine) republie l'interface Direction.
3. GitHub Actions compile l'APK : Actions → dernier run → artefact **VIC-CONNECT-debug-apk**.
