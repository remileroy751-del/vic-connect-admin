# VIC-CONNECT V6 — correction compilation Kotlin

Correction appliquée après le rapport GitHub Actions du 22/09/2026 :

- suppression de la double déclaration de `MobileNotification` ;
- `MobileNotification` est désormais défini une seule fois et partagé entre `MainActivity.kt` et `NotificationService.kt` ;
- les modèles de données retournés par les méthodes publiques de `VicApi` ne sont plus `private`, ce qui corrige les erreurs Kotlin « public exposes its private-in-file return type » ;
- aucune modification des migrations Supabase V5/V6 ni des fonctionnalités métier.

Le workflow GitHub reste : Java 17 + Android SDK 35 + Gradle 8.9 + `assembleDebug`.
