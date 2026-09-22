# VIC-CONNECT V6 — Mise à jour messages, notifications et session

## Nouveautés

- L'onglet admin **Communiqués** devient **Envoyer un message**.
- Destinataires disponibles :
  - À tous les parents
  - Aux parents d'une classe
  - À tous les enseignants
- Les enseignants disposent d'un écran **Messages de la Direction**.
- Les parents continuent à recevoir les messages de la Direction dans leur espace.
- Notifications Android système pour les nouveaux messages reçus.
- Service Android de surveillance en arrière-plan pour conserver la réception des notifications lorsque l'application n'est pas au premier plan.
- Session parent/enseignant conservée après fermeture de l'application.
- Au prochain lancement, l'espace est restauré automatiquement.
- Le bouton **Déconnexion** efface la session locale et exige à nouveau le code.

## Important : Supabase

Avant d'utiliser la nouvelle version Android, exécuter dans Supabase SQL Editor :

`supabase/migration-v6-messages-notifications.sql`

Cette migration ajoute les nouvelles cibles Direction, la lecture des messages Direction côté enseignant et le RPC de notifications Android.

## Notifications Android

Android 13+ demande l'autorisation **Notifications** au premier lancement. Elle doit être acceptée pour recevoir les notifications système.

L'application utilise un service Android de premier plan avec le type `remoteMessaging` pour surveiller les nouveaux événements. Une petite notification persistante indiquant que le service VIC-CONNECT est actif peut être visible pendant que la surveillance fonctionne.
