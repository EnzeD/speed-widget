# Speed Widget

Speed Widget est une app macOS minimaliste de barre des menus qui estime la qualité de la connexion Internet sans lancer de speed test permanent.

Le score sur 100 combine :

- la latence applicative vers un edge proche ;
- la gigue entre mesures successives ;
- les échecs de sonde assimilés à des pertes ;
- l'inflation de latence observée pendant l'activité naturelle du réseau ;
- une classe de capacité facultative obtenue avec un micro-test manuel.

## Lancer en développement

Prérequis : macOS 14 ou plus récent et Xcode 16 ou plus récent.

```sh
swift run SpeedWidget
```

L'icône Wi‑Fi et le score apparaissent dans la barre des menus. Il faut arrêter le processus depuis le terminal ou utiliser le bouton d'alimentation dans le panneau.

## Construire l'application

```sh
./scripts/package-app.sh
open "dist/SpeedWidget.app"
```

Le script produit une app signée localement dans `dist/SpeedWidget.app`.

## Tests

```sh
swift test
```

## Consommation réseau

- une requête de zéro octet est effectuée toutes les 5 secondes ;
- le score apparaît après trois sondes, sans lissage exponentiel ;
- la latence reflète environ 15 secondes et la stabilité environ 30 secondes ;
- l'intervalle passe à 15 secondes sur une connexion déclarée limitée par macOS ;
- les métriques de `URLSession` servent à comptabiliser approximativement les en-têtes et le coût de connexion ;
- la consommation journalière est affichée sans plafond ni arrêt automatique ;
- le micro-test est exclusivement manuel et plafonné à 2 Mo.

Le MVP utilise `https://speed.cloudflare.com/__down`, l'endpoint public du moteur Cloudflare Speedtest. Une requête `HEAD` vers Apple n'est déclenchée que pour confirmer une panne ou une latence supérieure à 500 ms. Aucun résultat analytique n'est envoyé par Speed Widget.

## Limites du MVP

- Les requêtes HTTPS mesurent une latence applicative, pas un ping ICMP brut.
- Une sonde HTTP perdue peut refléter un problème du serveur ; la sonde secondaire limite ce faux positif sans le supprimer totalement.
- Le micro-test de 2 Mo fournit une classe de capacité, pas une mesure exacte du débit maximal.
- La détection « en activité » repose sur les compteurs de l'interface réseau active et ne garantit pas que le lien soit saturé.
- Un VPN peut modifier le chemin mesuré et la sélection de l'interface observée.

La prochaine évolution naturelle est un petit endpoint QUIC dédié : un écho chiffré de quelques dizaines d'octets réduirait encore la consommation et rendrait la mesure des pertes plus directe.
