# Modèles 3D, textures et licences

Le prototype construit les personnages et la ville en code, avec des formes simples. Pour qu'ils ressemblent à de **vraies personnes**, il faut de vrais modèles 3D animés. Le code est déjà prêt à les recevoir.

## Personnage du joueur : la méthode la plus simple (Mixamo)

1. Crée un compte Adobe gratuit sur https://www.mixamo.com.
2. Choisis un personnage, ou importe le tien (voir plus bas).
3. Télécharge trois animations au format **FBX** : *Idle*, *Walking* et *Running*. La première avec « With Skin », les autres « Without Skin ».
4. Dans **Blender** (gratuit), importe les FBX. Renomme les animations `idle`, `walk` et `run`, puis exporte le tout en **`player.glb`**.
5. Copie le fichier dans `assets/characters/player.glb`.

Le jeu le détecte tout seul et l'utilise à la place du corps provisoire (voir `scripts/characters/humanoid.gd`). Le personnage doit regarder vers **-Z** (l'avant par défaut dans Godot).

Les animations et personnages Mixamo sont utilisables dans un jeu commercial. On n'a pas le droit de les revendre seuls.

## Avoir des personnages sénégalais crédibles

Les banques de modèles gratuites ont peu de personnages africains. Les options possibles :

- **MakeHuman** (gratuit, exports libres de droits CC0) : on règle le visage, la couleur de peau et la morphologie, puis on exporte vers Blender et Mixamo.
- **Character Creator / Reallusion** (payant) : rendu très réaliste. Vérifie la licence « game export ».
- **Commander à un artiste 3D**, idéalement sénégalais ou ouest-africain : c'est la meilleure option pour les vêtements (boubous, wax, foulards).
- Les tenues : textures de tissus wax et bazin à créer ou à acheter avec une licence commerciale.

## Textures réalistes (gratuites, CC0)

- https://polyhaven.com/textures : crépi, béton, sable, bitume, tôle
- https://ambientcg.com : la même chose, en libre de droits

Pour les utiliser, mets les fichiers dans `assets/textures/` et remplace les matériaux générés dans `city_generator.gd` (fonction `mat()`).

## Vraies rues de Dakar

Les données **OpenStreetMap** (licence ODbL, obligation de citer « © les contributeurs OpenStreetMap ») contiennent les rues et les bâtiments de Dakar. Plan prévu :

1. Exporter une zone (Médina, Plateau) depuis https://www.openstreetmap.org.
2. Convertir les rues et les contours des bâtiments en JSON.
3. Écrire un générateur qui lit ce JSON à la place du damier actuel.

## Règles à respecter

- Ne jamais utiliser de modèles, musiques ou images d'autres jeux, ni de marques réelles (logos d'opérateurs, d'équipes, etc.) sans autorisation.
- Garder une liste des ressources utilisées avec leur licence dans `assets/CREDITS.md`.
- Les lieux réels (monuments, places) peuvent être évoqués. On évite seulement d'utiliser des photos protégées.
