# Journal des modifications

## [Unreleased]

## [1.2.2] - 2026-03-17

### Modifié

- Refonte de l'édition des préréglages de disposition pour une expérience de configuration plus intuitive

## [1.2.1] - 2026-03-17

### Corrections

- Correction du dialogue « Déplacer vers Applications » affiché à tort au lieu de « Copier » lors du lancement depuis un DMG téléchargé (Gatekeeper App Translocation empêchait la reconnaissance du chemin de l'image disque)

## [1.2.0] - 2026-03-17

### Ajouté

- Changement de fenêtre cible : appuyez sur Tab / Maj+Tab pendant l'affichage de la grille pour parcourir les fenêtres disponibles
- Menu déroulant de fenêtre cible : cliquez sur la zone d'information de la cible pour sélectionner une fenêtre dans un menu contextuel
- Tab et Maj+Tab sont désormais réservés et ne peuvent pas être attribués comme raccourcis de disposition

## [1.1.8] - 2026-03-16

### Ajouté

- Après la copie depuis un DMG, proposition d'éjecter l'image disque et de placer le fichier DMG dans la Corbeille
- Détection d'un DMG Tiley monté au lancement depuis /Applications (par ex. après copie manuelle dans le Finder) avec proposition d'éjection et de mise à la Corbeille

## [1.1.7] - 2026-03-16

### Modifié

- Format de distribution changé de zip à DMG avec raccourci Applications et disposition Finder personnalisée (grandes icônes, fenêtre carrée)

### Corrections

- Correction de « Déplacer vers Applications » échouant avec une erreur de volume en lecture seule lors du lancement depuis un zip téléchargé sans déplacement préalable (Gatekeeper App Translocation)
- Affichage du dialogue « Copier vers Applications » au lieu de « Déplacer » lors du lancement depuis une image disque (DMG)

## [1.1.6] - 2026-03-16

### Corrections

- Correction de la fenêtre des réglages nécessitant deux activations pour s'ouvrir sur les configurations multi-écrans (icône de barre de menus, Cmd+, et menu Tiley → Réglages tous affectés)

## [1.1.5] - 2026-03-16

### Ajouté

- Superposition multi-écrans : la fenêtre de grille de disposition apparaît désormais simultanément sur tous les écrans connectés
- Mosaïque inter-écrans : faites glisser la grille ou cliquez sur un preset sur un écran secondaire pour placer la fenêtre cible sur cet écran
- La superposition de prévisualisation apparaît sur l'écran où la fenêtre du preset est affichée

### Corrections

- Correction de la disposition maximisée ne remplissant pas tout l'écran lors du mosaïquage entre écrans de tailles différentes
- Correction des raccourcis clavier locaux (touches fléchées, raccourcis de presets) ne fonctionnant plus après la deuxième activation de la superposition
- Correction de la fermeture partielle des fenêtres de superposition lors du clic sur une fenêtre d'app en arrière-plan ; toutes les fenêtres de superposition se ferment désormais ensemble
- Correction de la surbrillance de survol/sélection de preset apparaissant sur tous les écrans ; elle n'apparaît désormais que sur l'écran où se trouve le curseur de la souris

## [1.1.4] - 2026-03-15

### Corrections

- Correction du bouton « Afficher l'icône du Dock » ne fonctionnant pas : l'icône du Dock n'apparaissait pas à l'activation, et la désactivation faisait disparaître la fenêtre
- L'app ne se termine plus inopinément lorsque toutes les fenêtres sont fermées
- Correction de la cible de fenêtre par défaut étant Tiley lors du lancement par double-clic ; cible désormais correctement la fenêtre de l'app précédemment active
- Correction de la fenêtre principale apparaissant au lancement en tant qu'élément de connexion : la fenêtre ne s'ouvre plus au démarrage automatique du système

## [1.1.3] - 2026-03-15

### Corrections

- Correction de la superposition de prévisualisation de grille restant parfois visible à l'écran, provoquant l'empilement de superpositions en double

## [1.1.2] - 2026-03-15

### Ajouté

- Localisation : espagnol, allemand, français, portugais (Brésil), russe, italien

## [1.1.1] - 2026-03-15

## [1.1.0] - 2026-03-15

### Ajouté

- Prise en charge du mode sombre : tous les éléments de l'interface s'adaptent automatiquement au réglage d'apparence du système

### Modifié

- L'affichage des raccourcis utilise désormais des symboles (⌃ ⌥ ⇧ ⌘ ← → ↑ ↓) au lieu des noms de touches en anglais

### Corrections

- La fenêtre principale se masque désormais automatiquement lorsque Sparkle affiche le dialogue de mise à jour

## [1.0.1] - 2026-03-15

### Corrections

- Ajout de la localisation manquante pour les infobulles des boutons d'ajout de raccourci (« Ajouter un raccourci » / « Ajouter un raccourci global »)

## [1.0.0] - 2026-03-14

### Ajouté

- Invitation à déplacer l'app vers /Applications lors du lancement depuis un autre emplacement
- Drapeau global par raccourci : chaque raccourci au sein d'un preset de disposition peut désormais être défini individuellement comme global ou local
- Boutons d'ajout séparés pour les raccourcis réguliers et globaux, avec infobulles contextuelles instantanées

### Modifié

- Paramètre de raccourci global déplacé du niveau preset au niveau raccourci
- Les presets existants avec l'ancien drapeau global au niveau preset sont automatiquement migrés

## [0.9.0] - 2026-03-14

- Version initiale

### Ajouté

- Superposition de grille pour le mosaïquage de fenêtres avec taille de grille personnalisable
- Raccourci clavier global (Maj + Commande + Espace) pour activer la superposition
- Faire glisser sur les cellules de la grille pour définir la zone de fenêtre cible
- Presets de disposition pour enregistrer et restaurer les arrangements de fenêtres
- Prise en charge multi-écrans
- Option de lancement à la connexion
- Localisation : anglais, japonais, coréen, chinois simplifié, chinois traditionnel
