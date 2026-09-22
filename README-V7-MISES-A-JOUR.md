# VIC-CONNECT V7 — Mise à jour des messages de la Direction

Cette version ajoute les changements demandés :

- Destinataires Direction :
  - À tous les parents
  - Aux parents d'une classe
  - À tous les enseignants
  - À un enseignant
- L'option Élève est supprimée de l'interface Direction.
- Importance : uniquement **Urgent** et **Pas urgent**.
- Les anciennes importances sont automatiquement converties par la migration V7 : `rouge` → `urgent`, toutes les autres → `pas_urgent`.
- Les enseignants reçoivent réellement les messages ciblés sur leur propre compte ainsi que ceux envoyés à tous les enseignants.
- Les notifications Android de la Direction prennent également en compte le ciblage d'un enseignant précis.
- Le bouton côté parent et côté enseignant est désormais **Message de la Direction**.

## Base Supabase

Après avoir installé l'APK, exécuter **une seule fois** :

`supabase/migration-v7-direction-targets-importance.sql`

La migration doit être exécutée après V6.
