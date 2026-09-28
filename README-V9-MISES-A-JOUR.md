# VIC-CONNECT V9 — Messages Direction

## Modifications
- Les communiqués de la Direction destinés aux parents sont désormais correctement retournés par `student_announcements()`.
- Dans Super Admin > Envoyer un message, chaque communiqué possède une case de sélection.
- Une case globale permet de tout sélectionner.
- Le bouton **Supprimer la sélection** permet de retirer un ou plusieurs communiqués.
- La suppression est sécurisée côté Supabase par `admin_delete_announcements()` et supprime aussi les accusés de réception liés.
- Une fois supprimé, le communiqué n'est plus retourné aux parents/enseignants et ne peut donc plus apparaître dans leurs espaces ni dans les nouvelles notifications.
- La notification permanente du service Android n'affiche plus le texte « Vous serez averti(e) des nouveaux messages ». Les vraies notifications de nouveaux messages restent inchangées.

## SQL Supabase
Exécuter une seule fois :
`supabase/migration-v9-messages-direction-suppression.sql`

La migration doit être exécutée après V6, V7 et V8.
