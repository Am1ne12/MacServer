# Changelog

## 1.0.0 — 2026-11-17

Première version publique.

- Mode serveur automatique sur secteur : veille système désactivée, capot fermé compris.
- Comportement normal sur batterie : le Mac s'endort quand le capot se ferme.
- Réveil au branchement du chargeur via `acwake`, puis maintien éveillé par le service.
- Mode optionnel « serveur sur batterie » avec arrêt automatique à 20 %.
- Verrouillage de l'écran à la fermeture du capot.
- Icône dans la barre des menus : serveur secteur, portable/pause, serveur batterie, alerte.
- Menu : pause/reprise, mode batterie, verrouillage immédiat, journal, désinstallation.
- CLI `macserver` : `status`, `pause`, `resume`, `battery on|off`.
- Service LaunchDaemon root, démarrage au boot, redémarrage automatique en cas d'arrêt.
- Application universelle Apple Silicon + Intel.
- Installeur DMG avec notice et désinstallation propre.
