# Objets ramassables

Le système sépare la définition d'un type d'objet et son exemplaire dans le monde.

- `scripts/items/item_data.gd` définit la ressource `ItemData`.
- `resources/items/*.tres` contient les définitions : nom, modèle, collision,
  masse et décalage en main.
- `Scenes/items/world_item.tscn` est la scène physique commune (`RigidBody3D`).
- `scripts/items/item_interactor.gd` permet au joueur de viser, prendre et lâcher.

Les ressources peuvent être partagées par plusieurs exemplaires. Le porteur,
la position et les vitesses appartiennent à chaque exemplaire physique.
Ce découpage suit le principe des [ressources personnalisées de Godot](https://docs.godotengine.org/en/stable/tutorials/scripting/resources.html).

## Essayer

Lancer le jeu, héberger une partie et regarder les objets placés devant les
points d'apparition : une potion et une pierre. Le texte sous le viseur indique
l'objet ciblé.

- **E** : prendre l'objet visé, à moins de 2,5 mètres, si la main est libre.
- **G** : lâcher l'objet tenu. Sa physique reprend et il hérite de la vitesse
  du joueur.

La main est un point `HandAnchor` devant la caméra. L'objet suit le regard et
l'abaissement de la caméra pendant l'accroupissement. Cela ne crée pas une
animation de doigts ou de bras ; un attachement à l'os de la main pourra remplacer
ce point quand les animations de port seront disponibles.

## Ajouter un type d'objet

1. Créer une scène de modèle avec un `Node3D` à la racine et les meshes comme
   enfants, sans corps physique. Centrer le modèle sur son origine et garder
   une échelle adaptée au personnage.
2. Dans le panneau Fichiers, créer une ressource `ItemData`, ou dupliquer
   `resources/items/potion.tres`, puis l'enregistrer sous un autre nom.
3. Renseigner `Id`, `Display Name`, `Model`, `Mass` et `Collision Shape`.
   Utiliser une forme simple ou convexe adaptée à la taille du modèle.
4. Instancier `Scenes/items/world_item.tscn` sous `Items` dans le monde.
5. Affecter la ressource au champ **Data** de cette instance. Au lancement,
   le même script charge le modèle, la forme et la masse correspondants.
6. Ajuster `Held Position` et `Held Rotation Degrees` dans la ressource pour
   aligner cet objet en main. Le placement commun se règle sur le `HandAnchor`
   de `Scenes/player.tscn`.

Changer la ressource **Data** suffit à changer le type d'une instance. Les deux
exemples utilisent exactement la même scène physique et les mêmes scripts.

## Multijoueur

L'hôte conserve l'autorité sur les objets, simule leur physique au sol et
réplique leur position, rotation et identifiant de porteur. Le client demande
une prise ou un lâcher via RPC ; l'hôte vérifie le joueur, la portée, la visibilité
et la disponibilité de la main.

Un objet tenu reste sous `Items` pour garder un chemin réseau stable. Il est
figé, ses collisions sont suspendues et il suit le `HandAnchor` du porteur sur
chaque machine. Le lâcher est refusé si sa forme se trouve dans un obstacle.
Si le porteur disparaît, l'hôte libère l'objet.

Les définitions `.tres` font partie du projet sur toutes les machines ; elles
ne sont pas envoyées comme ressources par `MultiplayerSynchronizer`. Les objets
d'exemple sont placés dans la scène du monde. Pour en créer ou supprimer pendant
la partie, ajouter un `MultiplayerSpawner` dédié aux objets.
Si le type d'un objet doit changer pendant une partie réseau, répliquer aussi
son identifiant de définition, puis charger la ressource correspondante sur
chaque machine. Le champ `Data` est actuellement choisi dans l'éditeur.

## Vérification

```sh
godot --headless --path . --script res://tests/test_items.gd
```

Le test couvre la configuration E/G, le raycast, le remplacement de ressource, la physique,
le suivi en main, les obstacles, l'exclusivité et la disparition du porteur.
Il ouvre aussi une connexion ENet locale entre un hôte et un client pour vérifier
les RPC et la réplication.

Pour vérifier uniquement la partie locale sans ouvrir de connexion réseau :

```sh
godot --headless --path . --script res://tests/test_items.gd -- --local
```
