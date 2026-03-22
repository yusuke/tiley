# Journal des modifications

## [Unreleased]

### Ajouté

- Intégration du SDK TelemetryDeck pour des statistiques d'utilisation respectueuses de la vie privée (ouverture de la grille, application de disposition, application de préréglage, modification des paramètres)
- Les fenêtres de la barre latérale sont regroupées par écran et par application ; les apps multi-fenêtres affichent un en-tête avec des lignes indentées
- Les en-têtes d'écran dans la barre latérale disposent d'un menu avec les actions « Rassembler les fenêtres » et « Déplacer les fenêtres vers » pour gérer les fenêtres entre écrans
- Menu de l'en-tête d'application avec « Déplacer toutes les fenêtres vers un autre écran », « Masquer les autres » et « Quitter »
- Menu des apps à fenêtre unique avec « Déplacer vers un autre écran », « Masquer les autres » et « Quitter »
- Les écrans vides (sans fenêtres) sont affichés dans la barre latérale avec leur en-tête

### Modifié

- L'arrière-plan de la grille reflète désormais fidèlement les paramètres d'affichage du fond d'écran macOS (remplir, ajuster, étirer, centrer et mosaïque), avec une mise à l'échelle correcte des tuiles, le ratio de pixels physiques pour le mode centré et la couleur de remplissage pour les zones letterbox
- L'aperçu de la grille de mise en page affiche désormais la barre des menus, le Dock et l'encoche, offrant une représentation plus fidèle de l'écran réel

### Corrigé

- Correction d'un problème où la fenêtre se déplaçait vers une position inattendue après redimensionnement lorsqu'elle était déjà à la position cible. Contournement de la déduplication AX par pré-décalage
- Réduction du scintillement lors du redimensionnement sur les écrans non principaux. Le redimensionnement est d'abord tenté sur place ; le rebond vers l'écran principal n'a lieu qu'en cas d'échec complet
- Lors du rebond vers l'écran principal, la fenêtre est désormais placée en bas de l'écran (presque hors champ) au lieu du coin supérieur gauche, minimisant le scintillement

## [2.2.0] - 2026-03-21

### Modifié

- Les cellules de grille non sélectionnées sont désormais transparentes
- Le rapport d'aspect de la grille correspond maintenant à la zone visible de l'écran (sans barre de menus ni Dock) ; si la grille serait trop haute, sa largeur est réduite proportionnellement pour garantir l'affichage d'au moins 4 presets
- L'arrière-plan de la grille de mise en page affiche désormais l'image du bureau (semi-transparent, coins arrondis)
- Les cellules sélectionnées par glissement sont désormais semi-transparentes, laissant apparaître l'image du bureau
- La surbrillance au survol des presets dans la grille utilise désormais le même style que la sélection par glissement

### Ajouté

- La barre latérale de liste de fenêtres est désormais affichée sur tous les écrans dans les configurations multi-moniteurs, pas seulement sur l'écran cible
- L'état de la barre latérale (visibilité, élément sélectionné, texte de recherche) est synchronisé entre toutes les fenêtres d'écran
- Journal de débogage de redimensionnement optionnel (`~/tiley.log`) (Réglages > Débogage)

### Corrigé

- Correction du placement de fenêtre utilisant une géométrie d'écran obsolète lorsque le Dock ou la barre des menus s'affichait/masquait automatiquement pendant que la superposition était ouverte
- Correction du redimensionnement échouant sur les écrans non principaux dans les configurations DPI mixtes ; la fenêtre est temporairement déplacée vers l'écran principal pour le redimensionnement puis placée à la position cible
- Correction de la position non appliquée après redimensionnement lorsque certaines apps annulent silencieusement les changements de position (contournement de la déduplication AX)
- Lorsque la taille minimale de fenêtre d'une app empêche la taille demandée, la position est recalculée pour que la fenêtre reste dans la zone visible de l'écran
- Suppression du scintillement visible des fenêtres lors du changement de fenêtre cible entre écrans ; les fenêtres ne sont plus recréées lors du changement d'écran

## [2.1.0] - 2026-03-20

### Ajouté

- Double-clic sur une fenêtre dans la barre latérale pour la mettre au premier plan et fermer la grille de disposition
- Menu contextuel (bouton points de suspension) sur les lignes de fenêtres de la barre latérale avec trois actions :
  - « Fermer les autres fenêtres de [App] » — ferme les autres fenêtres de la même app (affiché uniquement quand l'app a plusieurs fenêtres)
  - « Quitter [App] » — ferme l'application
  - « Masquer les fenêtres sauf [App] » — masque toutes les autres applications (équivalent Cmd-H), affiche l'app sélectionnée si elle était masquée
- Les applications masquées (Cmd-H) apparaissent désormais dans la barre latérale comme entrées de remplacement (nom de l'app uniquement) et sont affichées à 50 % d'opacité
- La sélection d'une app masquée (Entrée, double-clic, redimensionnement grille/disposition) la rend automatiquement visible et opère sur sa fenêtre au premier plan

## [2.0.3] - 2026-03-19

### Ajouté

- Rappels de mise à jour discrets de Sparkle : lorsqu'une vérification en arrière-plan trouve une nouvelle version, un point rouge apparaît sur l'icône de la barre des menus et des labels « Mise à jour disponible » s'affichent à côté du bouton engrenage et du bouton « Vérifier les mises à jour » dans les réglages
- Si l'icône de la barre des menus est masquée, elle s'affiche temporairement avec le badge lors de la détection d'une mise à jour, puis se masque à nouveau à la fin de la session

### Modifié

- La fenêtre des réglages est désormais masquée lorsque Sparkle trouve une mise à jour (auparavant uniquement au début du téléchargement) et restaurée en cas d'annulation
- Le titre de la fenêtre des réglages est maintenant localisé dans toutes les langues prises en charge
- Le numéro de version a été déplacé du titre des réglages vers la section Mises à jour, à côté du bouton « Vérifier les mises à jour »

## [2.0.2] - 2026-03-19

### Ajouté

- Bouton de fermeture dans les lignes de la barre latérale des fenêtres : au survol du nom d'une fenêtre, un bouton × apparaît pour la fermer
- Réglage « Quitter l'app en fermant la dernière fenêtre » (Réglages > Fenêtres) : lorsqu'il est activé (par défaut), fermer la dernière fenêtre d'une app quitte l'app ; lorsqu'il est désactivé, seule la fenêtre est fermée
- L'infobulle du bouton de fermeture affiche le nom de la fenêtre ; lorsque l'action quittera l'app, le nom de l'app est affiché
- Raccourci clavier « / » pour fermer la fenêtre sélectionnée (ou quitter l'app s'il s'agit de la dernière fenêtre et que le réglage est activé)

## [2.0.1] - 2026-03-19

### Modifié

- Panneau de réglages redessiné dans le style Tahoe : sections avec fond en verre (Liquid Glass sur macOS 26+), barre d'outils compacte avec boutons retour/quitter, et lignes groupées style iOS avec contrôles intégrés

## [2.0.0] - 2026-03-19

### Modifié

- Le menu déroulant de sélection de fenêtre cible a été remplacé par un panneau latéral avec Liquid Glass (macOS Tahoe) ; comprend un champ de recherche avec prise en charge complète de l'IME, navigation par touches fléchées et Tab/Maj+Tab, et Cmd+F pour basculer la visibilité

### Amélioré

- Les fenêtres dans le panneau latéral sont listées en ordre Z (avant vers arrière) plutôt que regroupées par application
- Les fenêtres non standard (palettes, barres d'outils, etc.) sont filtrées de la liste des fenêtres cibles afin de n'afficher que les fenêtres de document redimensionnables

## [1.2.7] - 2026-03-18

### Amélioré

- La fenêtre principale se ferme automatiquement lorsque Sparkle commence à télécharger une mise à jour

### Corrigé

- Suppression des jointures visibles dans l'aperçu des contraintes de redimensionnement lorsque les zones de dépassement (rouge) ou de sous-capacité (jaune) sont affichées simultanément dans les deux directions

## [1.2.6] - 2026-03-18

### Corrigé

- Lors du redimensionnement d'une fenêtre d'arrière-plan de la même application via le cycle Tab, la fenêtre est désormais mise au premier plan si elle serait masquée par d'autres fenêtres de cette application

## [1.2.5] - 2026-03-18

### Ajouté

- Détection des contraintes de redimensionnement des fenêtres : détecte automatiquement la possibilité de redimensionnement par axe grâce à une vérification rapide en 3 étapes (non redimensionnable → bouton plein écran → sonde de 1px en dernier recours)
- L'aperçu de disposition affiche désormais des zones rouges là où la fenêtre ne peut pas s'agrandir et des zones jaunes là où elle ne peut pas se réduire, offrant un retour visuel sur les contraintes de taille avant application

## [1.2.4] - 2026-03-17

### Amélioré

- Interface d'édition des préréglages de disposition affinée : bouton de suppression déplacé à côté du bouton de confirmation, boutons d'édition/action placés dans une colonne dédiée pour éviter le chevauchement avec les raccourcis
- La sélection de la grille est désormais modifiable en mode édition : glissez sur la grille pour mettre à jour la position du préréglage avec aperçu en direct et mise en surbrillance

## [1.2.3] - 2026-03-17

### Amélioré

- Peaufinage de l'interface d'édition des préréglages de disposition : le bouton de suppression s'affiche en superposition sur l'aperçu de la grille, avec dialogue de confirmation, arrière-plan opaque au survol et style de bouton uniforme

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
