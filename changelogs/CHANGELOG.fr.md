# Journal des modifications

## [Unreleased]

### Corrigé

- Lors de la modification d'un préréglage de disposition contenant déjà des emplacements assignés à des apps, le numéro affiché dans le rectangle en cours de glissement (et sa couleur) était trop élevé d'une unité : les emplacements assignés étaient comptés alors qu'ils affichent une icône au lieu d'un numéro. Les aperçus de glissement et de survol utilisent désormais la même numérotation que les rectangles validés.
- Tiley effectuait un balayage complet de l'Accessibilité sur toutes les fenêtres ouvertes (plus une requête de la liste des fenêtres auprès du WindowServer) à chaque changement de focus ou de fenêtre dans n'importe quelle application — même lorsque la fonction de groupement de fenêtres n'était pas utilisée du tout. Le rafraîchissement des badges retourne désormais immédiatement lorsqu'il n'existe ni groupe lié ni candidat de groupe en attente, et les événements de changement de focus sont regroupés afin qu'un seul changement de fenêtre (qui déclenche à la fois les notifications d'Accessibilité « fenêtre focalisée » et « fenêtre principale ») ne provoque au plus qu'un rafraîchissement au lieu de deux. Cela supprime la charge CPU/IPC permanente lors des changements d'application ordinaires.
- La surcouche de Tiley relisait depuis le disque les métadonnées du fond d'écran et la configuration du Dock à chaque passe de rendu SwiftUI : la plist du Store de fonds d'écran était réanalysée jusqu'à quatre fois par passe (et le fichier du fond d'écran rouvert pour lire ses dimensions en pixels), et lorsqu'un bord du Dock était visible, la plist du Dock ainsi que toutes les icônes de ses applications étaient rechargées à chaque fois — des E/S disque synchrones sur le thread principal à la fréquence des mouvements de souris. Les informations d'affichage du fond d'écran sont désormais mises en cache par écran et invalidées lorsque le fond d'écran ou la configuration des écrans change, et le contenu du Dock n'est lu qu'une seule fois à chaque ouverture de la fenêtre.
- Faire glisser une sélection sur la grille reconstruisait la surcouche d'aperçu de l'écran à chaque événement de souris : chaque mouvement recréait entièrement la hosting view SwiftUI de la surcouche, même lorsque les cellules surlignées n'avaient pas changé. L'aperçu ne se met désormais à jour que lorsque la sélection passe réellement à une autre cellule, et la surcouche réutilise une seule hosting view au lieu de la reconstruire — supprimant le pic de CPU pendant le glissement (la même réutilisation s'applique aux aperçus de survol des préréglages, de redimensionnement et de la grille des réglages).
- Déplacer ou redimensionner un groupe de fenêtres liées interrogeait à 120 Hz avec des appels d'Accessibilité synchrones, y compris jusqu'à trois allers-retours de vérification-correction par fenêtre suiveuse à chaque tick lors du redimensionnement, et recherchait les fenêtres par balayage linéaire des centaines de fois par seconde. L'interrogation fonctionne désormais à 60 Hz avec une seule passe de vérification par tick (la correction au relâchement fixe toujours les positions finales), les recherches de fenêtres passent par un index en O(1), et les applications suiveuses reçoivent un court délai d'attente de messagerie d'Accessibilité pendant le glissement, si bien qu'une application occupée ne peut plus bloquer Tiley en plein glissement.
- Avec des groupes liés ou des badges de groupement actifs, les opérations de groupe relisaient les positions des fenêtres bien plus souvent que nécessaire : former, dissoudre ou revalider un groupe balayait la position de chaque fenêtre ouverte via des lectures d'Accessibilité synchrones plusieurs fois par événement (un seul clic sur une fenêtre appariée pouvait déclencher six à huit balayages complets), et les rafraîchissements de badges balayaient toutes les fenêtres à chaque changement de focus. Tous ces chemins ne lisent désormais que les fenêtres réellement concernées (membres du groupe et candidats aux badges), de sorte que le trafic d'Accessibilité par événement ne croît plus avec le nombre total de fenêtres ouvertes.
- L'application d'une disposition ne bloque plus l'application. La séquence de déplacement des fenêtres (qui attend délibérément entre les étapes d'Accessibilité pour venir à bout des apps qui rétablissent leur position) s'exécutait en série sur le thread principal : un préréglage à quatre fenêtres bloquait Tiley 200 ms ou plus, plus environ 100 ms par app pour la séquence de mise au premier plan. Les déplacements s'exécutent désormais sur des threads d'arrière-plan, les fenêtres indépendantes sont déplacées en parallèle, les attentes de mise au premier plan ne bloquent plus le thread principal, et les applications répétées rapides sont mises en file d'attente en conservant leur ordre. La temporisation des étapes d'Accessibilité par fenêtre est inchangée.
- La recherche fenêtre→Space émettait une requête WindowServer par fenêtre à chaque rafraîchissement de la liste des fenêtres (c'est-à-dire après chaque changement d'app). Les affectations de Space disposent désormais d'un cache de courte durée (cinq secondes au maximum, vidé lors des changements de Space), et le moniteur des groupes répartis sur plusieurs Spaces — qui contourne volontairement le cache — vérifie toutes les deux secondes au lieu de chaque seconde.
- Les lignes de la barre latérale résolvaient leurs partenaires de lien de groupe par balayages linéaires et requêtes de bundle par ligne à chaque passe de rendu, et un défaut de cache faisait que la recherche du nom d'app utilisée par le champ de recherche relisait l'Info.plist depuis le disque à chaque utilisation pour la plupart des apps (le résultat négatif n'était jamais enregistré). La résolution des partenaires se termine désormais immédiatement pour les fenêtres sans lien et utilise des recherches indexées, et les deux caches de noms enregistrent aussi les résultats négatifs.
- La première frappe de changement de fenêtre après l'ouverture de la surcouche, ainsi que la résolution de la cible sur plusieurs chemins, exécutaient encore une énumération d'Accessibilité complète et synchrone de toutes les fenêtres ouvertes sur le thread principal — un blocage de plus de 100 ms avec de nombreuses fenêtres. Les deux réutilisent désormais la liste déjà alignée sur l'ordre réel des fenêtres à l'ouverture, ne recourant à une capture synchrone que lorsqu'aucune liste n'existe (premier lancement) ; le rafraîchissement d'arrière-plan faisant autorité effectue la réconciliation quelques instants plus tard.
- Sur les configurations multi-écrans, chaque écran n'hébergeant pas l'icône d'état de la barre des menus rééchantillonnait son fond d'écran à chaque passe de rendu pour choisir la couleur du texte de la barre des menus miniature — avec rastérisation de l'image et histogramme d'environ 50 000 pixels par passe. La couleur échantillonnée est désormais mise en cache par écran et recalculée uniquement lorsque le fond d'écran ou la configuration des écrans change.
- Avec des liens satellites enregistrés, chaque événement de déplacement ou de redimensionnement de n'importe quelle fenêtre interrogeait Launch Services une fois par bundle d'app enregistré avant même de vérifier si la fenêtre déplacée faisait partie d'une paire — répété de nombreuses fois par seconde pendant tout glissement de fenêtre. La vérification de pertinence s'exécute désormais en premier avec des comparaisons d'identifiants peu coûteuses, et la requête de bundle n'a lieu que pour les événements impliquant réellement une paire liée.
- Les boutons déroulants de la barre d'actions (déplacer vers un écran / redimensionner) forçaient un redessin AppKit complet à chaque passe de mise à jour SwiftUI — à la fréquence du survol ou des frappes — et chaque redessin re-teintait leurs images SF Symbol en copiant et re-rendant les bitmaps. Les boutons ne se redessinent désormais que lorsqu'une entrée réellement utilisée par le dessin change, et les images de symboles teintées sont mises en cache par symbole, taille, teinte et apparence (les changements de thème rendent toujours des couleurs fraîches).
- Les panneaux de badges de groupement étaient entièrement re-rendus à chaque rafraîchissement des badges — chaque rafraîchissement reconstruisait l'arborescence de vues SwiftUI de chaque badge et redéfinissait la position de son panneau même sans aucun changement. Les badges se comparent désormais à leur état précédent et sautent le re-rendu lorsque position, état et indicateurs de survol sont tous inchangés.
- Les actions de fenêtres en masse (déplacer toutes les fenêtres d'une app ou d'un écran entier vers un autre moniteur, fermer plusieurs fenêtres, masquer des apps) planifiaient un rafraîchissement complet de la liste des fenêtres par fenêtre concernée. Elles sont désormais regroupées en un seul rafraîchissement différé, de sorte que le coût après action reste constant quel que soit le nombre de fenêtres impliquées.
- Chaque lancement depuis le dossier Applications lançait de manière synchrone `hdiutil info` (qui peut prendre des centaines de millisecondes) sur le thread principal pour vérifier si une image disque Tiley était encore montée — et, en cas de découverte, exécutait un second `hdiutil` uniquement pour résoudre un chemin que la première requête avait déjà renvoyé. La détection s'exécute désormais en arrière-plan et ne revient sur le thread principal que lorsqu'une image montée est réellement trouvée ; la seconde requête redondante a disparu, et le nettoyage éjection/corbeille après relance ne bloque plus le démarrage.
- La fenêtre des réglages résolvait à nouveau les empreintes d'identité des écrans connectés et reconstruisait le jeu de préréglages par défaut à chaque passe de rendu — à chaque tick pendant le glissement des curseurs de grille. Les deux sont désormais mémoïsés et recalculés uniquement lorsque la configuration des écrans ou la taille de la grille change réellement.
- Modifier un préréglage (renommage, affectation d'apps, édition de rectangles) désinscrivait et réinscrivait tous les raccourcis globaux de préréglages à chaque changement, et le réordonnancement aussi. Les raccourcis ne sont désormais réinscrits que lorsqu'une modification touche réellement les raccourcis d'un préréglage ; le réordonnancement et les nouveaux préréglages l'évitent entièrement.
- Avec la journalisation de débogage activée, chaque ligne ouvrait, complétait puis fermait le fichier journal — rendant les chemins haute fréquence limités par les E/S précisément pendant leur mesure. Le descripteur de fichier est désormais ouvert une seule fois et réutilisé.
- Le bouton de redimensionnement de la barre latérale lisait la position de la fenêtre via un appel d'Accessibilité synchrone vers l'app cible — et recherchait son icône — à chaque passe de rendu SwiftUI (chaque survol, frappe ou survol de préréglage, une fois par écran). Une app cible occupée pouvait faire saccader la superposition à chaque passe. La position n'est désormais lue qu'une fois à l'ouverture effective du menu de redimensionnement, l'icône provient du cache par fenêtre, et la liste des préréglages de taille adaptés à l'écran est mise en cache par taille d'écran.
- Chaque début de glisser sur la grille — et chaque sortie puis retour du pointeur — détruisait la fenêtre plein écran d'aperçu de disposition et en créait une nouvelle (un nouveau NSWindow avec sa vue hôte et un backing store de la taille de l'écran) ; de plus, en glissant hors de la grille, chaque événement souris réécrivait l'état du préréglage sélectionné et faisait re-rendre la superposition sur tous les écrans au rythme des événements souris. La fenêtre d'aperçu reste désormais en vie tant que l'interface de Tiley est ouverte et n'est libérée qu'à la fermeture de la superposition ou lors d'un changement de configuration d'écrans ; le glisser hors grille ne signale la transition qu'une fois, et les écritures de sélection de préréglage sans changement sont ignorées.
- La couche modèle interrogeait Launch Services pour les icônes d'apps et les identifiants de bundle à chaque passe de rendu SwiftUI et à chaque changement de cellule (aperçu des fenêtres du mini-bureau, aperçu de disposition en direct et survol des préréglages, qui parcourait deux fois toutes les fenêtres ouvertes), et comme chaque requête renvoyait un nouvel objet icône, les vues d'aperçu ne pouvaient jamais être reconnues comme inchangées. Ces requêtes passent maintenant par un cache par processus (vidé à la fin du processus), si bien que des entrées identiques donnent des valeurs identiques et que les vues évitent le re-rendu ; la fenêtre d'aperçu ne redemande plus non plus son passage au premier plan à chaque changement de cellule.
- Tiley observe toutes les fenêtres pour détecter déplacements et redimensionnements afin de proposer les badges « former un groupe », et à chaque événement il relisait la position et la taille de la fenêtre via deux appels d'Accessibilité synchrones vers l'app — puis jetait le résultat. Tout glisser de fenêtre dans n'importe quelle app coûtait donc deux allers-retours par événement vers l'app déplacée. Cette lecture a disparu ; les notifications de changement de fenêtre focalisée et de fenêtre principale (toutes deux émises pour un seul clic) déclenchent désormais la liaison d'élévation une fois au lieu de deux, et les notifications au niveau de l'app sont enregistrées une fois par app au lieu d'une fois par fenêtre.
- Chaque changement d'application (Cmd-Tab ou clic dans une autre app) exécutait une requête de liste de fenêtres auprès du WindowServer et un tri complet de la liste de fenêtres en cache de Tiley dont le résultat n'était jamais affiché (la superposition réaligne le cache dès son ouverture), puis 200 ms plus tard une requête d'Accessibilité synchrone vers l'app venant d'être activée, même sans aucun groupe de fenêtres — si bien qu'une app qui ne répondait pas pouvait bloquer Tiley pendant les six secondes du délai par défaut. Le réalignement redondant est supprimé, la vérification des groupes précède désormais tout appel d'Accessibilité, l'indicateur d'autorisation d'accessibilité n'est écrit que lorsqu'il change réellement, et Tiley définit maintenant un délai d'Accessibilité d'une seconde pour tout le processus, de sorte qu'une app figée ne peut plus le bloquer pendant plusieurs secondes.
- Au relâchement d'une fenêtre après un déplacement ou un redimensionnement — dans n'importe quelle app —, Tiley relisait la position et la taille de toutes les fenêtres ouvertes via des appels d'Accessibilité synchrones (deux par fenêtre, sur le thread principal) pour vérifier si la fenêtre déplacée en touchait désormais une autre. Avec 30 à 40 fenêtres, cela représentait 60 à 80 allers-retours par glisser, et la même passe pouvait s'exécuter deux fois par geste. La détection ne lit plus que les fenêtres déplacées et les fenêtres à l'écran dont les limites actuelles se trouvent à proximité (obtenues par une seule requête de liste de fenêtres), et le minuteur de stabilisation est réarmé au lieu d'être recréé à chaque événement de déplacement.
- Après l'application d'une disposition, les fenêtres que Tiley venait de placer étaient parfois traitées comme si l'utilisateur les avait déplacées à la main : les notifications de déplacement d'Accessibilité envoyées en retard par les apps arrivaient après la fin de la suppression des propres déplacements de Tiley, ce qui lançait la détection d'adjacence des déplacements manuels sur toutes les fenêtres à l'écran et affichait des badges « former un groupe » entre une fenêtre placée et une fenêtre sans rapport située derrière dont le bord coïncidait par hasard — un bord tout juste groupé pouvait ainsi afficher un badge de lien supplémentaire. Tiley enregistre désormais les cadres des fenêtres qu'il place afin de reconnaître ces notifications tardives comme des échos de ses propres déplacements.
- Plusieurs petits travaux par passe de rendu de la fenêtre superposée étaient répétés à chaque survol, frappe ou glisser, une fois par écran : le nom de chaque écran était redemandé au pilote d'affichage pour les en-têtes de la barre latérale, les métadonnées du fond d'écran et l'écran prévisualisé étaient résolus trois à quatre fois, le préréglage en cours d'édition et celui survolé étaient recherchés jusqu'à neuf fois chacun pour alimenter la grille, chaque vignette de préréglage rebalayait tous ses rectangles pour chaque cellule et, dès qu'un groupe de fenêtres ou une paire satellite existait, chaque ligne de la barre latérale reconstruisait ses propres tables de recherche pour les badges de lien. Les noms d'écran sont désormais mis en cache, les entrées écran / fond d'écran / préréglage sont résolues une fois par passe, la barre latérale construit ses tables de lien une seule fois et les partage entre les lignes, et les vignettes de préréglage comparent leurs entrées et sautent le rendu quand rien n'a changé.
- La superposition pouvait rester à l'écran après un clic sur la fenêtre d'une autre app. Sous macOS 14 et versions ultérieures, le système peut refuser de rendre Tiley active lorsque le raccourci est pressé juste après une interaction avec une autre app (par exemple immédiatement après avoir cliqué sur une autre fenêtre pour fermer la superposition précédente) ; la superposition était alors visible sans que Tiley soit active, si bien qu'un clic ailleurs ne provoquait jamais la désactivation qui la masque. Tiley vérifie désormais l'activation peu après l'affichage de la superposition et la retente, et — si elle est toujours refusée — un clic en dehors des fenêtres de Tiley masque directement la superposition.
- Chaque capture de la liste des fenêtres (exécutée en arrière-plan après chaque changement d'app et à chaque ouverture de la superposition) effectuait trois ou quatre allers-retours d'Accessibilité distincts par fenêtre — sous-rôle, position, taille puis titre — et, pour chaque fenêtre, récupérait à nouveau la liste des apps en cours, créait un nouvel élément d'application d'Accessibilité et ré-énumérait les écrans. Elle copiait aussi deux fois la liste des fenêtres à l'écran uniquement pour vérifier Show Desktop / Mission Control. Les attributs de chaque fenêtre sont désormais obtenus en un seul aller-retour, la liste des apps, les éléments d'application et la liste des écrans sont rassemblés une fois par capture, et les deux vérifications partagent une seule copie de la liste des fenêtres.
- Les opérations sur les groupes de fenêtres refaisaient plusieurs fois le même travail par action de l'utilisateur : dissoudre un groupe déclenchait une revalidation complète de tous les autres groupes (en relisant le cadre de chaque membre via l'Accessibilité) plus un rafraîchissement des badges, et le ré-appariement des satellites ou une scission de Space dissolvait deux groupes ou plus à la suite — un seul clic sur une fenêtre appariée pouvait ainsi exécuter quatre à cinq rafraîchissements de badges et sept à huit requêtes de liste de fenêtres ; lier, délier, l'expiration des candidats et la destruction de fenêtres lançaient chacun leur propre rafraîchissement immédiat ; l'application d'une disposition déliait les adjacences de bord d'écran une par une avec un rafraîchissement complet à chaque fois ; et un seul clic atteignait jusqu'à trois fois le gestionnaire de mise au premier plan du groupe. Les dissolutions multiples revalident désormais une seule fois à la fin, les rafraîchissements terminaux sont regroupés sur le prochain tour de boucle d'exécution, la revalidation transmet au rafraîchissement les cadres déjà lus, le déliage préalable à la disposition scinde le groupe une seule fois sans rafraîchissement intermédiaire, et les envois répétés de mise au premier plan pour la même fenêtre dans un délai de 100 ms sont ignorés.
- Un seul compteur de version pilotait toutes les vues de la superposition dépendant de la liste des fenêtres, et il était incrémenté aussi bien pour les changements de sélection que de liste : une seule ouverture de la superposition l'avançait quatre à cinq fois, chaque clic dans la barre latérale deux fois, et chaque incrément vidait en outre le cache par app de la barre latérale (icône, identifiant de bundle, nom d'origine), si bien que le rendu suivant résolvait à nouveau l'app de chaque ligne via Launch Services et relisait son Info.plist. Le rafraîchissement en arrière-plan qui arrive après l'ouverture republiait aussi la liste même lorsqu'elle était identique à celle déjà affichée. Les changements de sélection avancent désormais un compteur distinct observé uniquement par les vues dépendant de la sélection, le cache par app n'est invalidé que lorsque l'ensemble des apps change réellement, et un rafraîchissement produisant la même liste ne la republie plus.
- Plusieurs actions de groupe bloquaient encore le thread principal avec la séquence synchrone de déplacement de fenêtres (qui attend délibérément entre les étapes d'Accessibilité) : remplir un groupe jusqu'au bord de l'écran attendait au moins 50 ms par membre, échanger deux fenêtres et égaliser leurs dimensions de même, et chaque changement de satellite restaurait la position de l'ancre — plus jusqu'à quatre vérifications de dérive — de la même manière, si bien qu'un clic sur un badge ou un changement de satellite pouvait figer Tiley pendant 100 à 250 ms (jusqu'à une seconde quand une app refuse le cadre). Confirmer une seule fenêtre avec Entrée pompait aussi la boucle d'exécution pendant 50 ms, et confirmer vers une app masquée laissait la superposition à l'écran pendant les 150 ms d'attente de réaffichage. Ces déplacements s'exécutent désormais sur des threads d'arrière-plan avec l'état du groupe mis à jour une fois qu'ils ont abouti (et la suppression du couplage de groupe maintenue jusque-là au lieu de 0,1 s fixe), la confirmation d'une seule fenêtre suspend au lieu de pomper, et les fenêtres de Tiley quittent l'écran avant l'attente de réaffichage.
- Après avoir égalisé les hauteurs (ou largeurs) de deux fenêtres liées, faire glisser l'une d'elles pouvait laisser la paire désalignée lorsque l'app signalait le glisser comme un déplacement et un redimensionnement simultanés (comme le fait macOS en défaisant la mosaïque d'une fenêtre remplissant l'écran) : la partenaire est invitée à suivre la translation perpendiculaire, mais certaines apps l'ignorent, et le calage au relâchement censé réaligner les bords partagés décidait s'ils étaient « partagés » d'après des caches que la résolution des écarts/chevauchements venait d'écraser avec le cadre réel de la partenaire — il concluait donc qu'ils ne l'étaient pas et laissait le décalage. Les bords partagés sont désormais enregistrés au début du glisser et le calage au relâchement utilise cet enregistrement.
- Survoler une ligne de la barre latérale des fenêtres de la superposition réévaluait tout le corps de la superposition sur cet écran — la composition d'écran, la grille avec ses fenêtres miniatures, chaque ligne de préréglage et la barre d'indications — parce que l'état de survol des lignes résidait dans la vue de premier niveau. La liste des lignes de la barre latérale est désormais une vue distincte qui possède cet état de survol, si bien que déplacer le pointeur le long de la liste ne redessine plus que les lignes.
- Deux coûts supplémentaires par rendu dans la superposition : déplacer le pointeur sur la grille recomparait chaque cellule de base (jusqu'à 144, chacune parcourant les sélections) parce que la cellule survolée était une entrée de toute la grille de cellules, et chaque réévaluation du corps de la superposition — un survol de préréglage, un changement de sélection, une frappe — reconstruisait de zéro la liste des lignes de la barre latérale et ses tables de recherche de liens alors que leurs entrées n'avaient pas changé. Les cellules de base sont désormais une vue distincte comparée par valeur avec le remplissage de survol dessiné en une seule superposition, et les lignes de la barre latérale et les tables de recherche sont mémorisées selon la liste des fenêtres, le texte de recherche, les Spaces, la configuration des écrans et l'état des groupes.
- Le chemin du raccourci portait plusieurs petits coûts à chaque appui ou fermeture : les builds de production demandaient à Launch Services, à chaque appui, si un build de débogage était en cours (l'indicateur est déjà maintenu par les observateurs de lancement/terminaison), le gestionnaire passait par une tâche avant d'ouvrir la superposition, chaque fermeture démontait et réenregistrait le raccourci principal inchangé et reconstruisait le résolveur d'empreintes d'écrans (qui lit le fabricant/modèle/numéro de série de chaque écran), et l'étape suivant l'ouverture copiait la liste des fenêtres à l'écran sur le thread principal pour détecter Show Desktop / Mission Control puis lisait la position de la fenêtre cible via un appel d'Accessibilité synchrone que le rafraîchissement de référence rendait redondant. L'appui ouvre désormais la superposition directement, le raccourci principal reste enregistré entre les fermetures, le résolveur est mémorisé selon la configuration des écrans, la vérification d'Exposé s'exécute hors du thread principal, et la lecture d'Accessibilité redondante a disparu.
- Faire défiler la fenêtre cible (Tab, touches fléchées ou clic dans la barre latérale) allouait une nouvelle fenêtre d'aperçu plein écran à chaque étape même lorsque la cible restait sur le même écran, forçait deux validations Core Animation synchrones par étape et lisait deux fois la position de chaque fenêtre masquante via l'Accessibilité. La fenêtre d'aperçu est désormais réutilisée dès que l'écran correspond, l'animation de déplacement commence simplement une image plus tard au lieu de forcer une validation, et chaque fenêtre masquante n'est lue qu'une fois.
- La première image de la superposition après un changement de fond d'écran, un basculement clair/sombre (fonds dynamiques), un changement d'écran ou le lancement décodait la vignette du fond de chaque écran — 30 à 150 ms par écran pour un grand HEIC — et lisait les métadonnées du Store des fonds sur le thread principal dans cette même image. Les deux sont désormais préparés en arrière-plan dès que le fond ou la configuration des écrans change (et au lancement), de sorte que la première image de la superposition les trouve prêts.
- Un fond d'écran choisi dans Réglages Système n'apparaissait dans les écrans miniatures de la superposition qu'après la fermeture du panneau Fond d'écran. macOS envoie la notification de changement d'image de bureau avant que Réglages Système ait écrit le nouveau choix dans le Store des fonds, si bien que Tiley lisait — et mettait en cache — le fond précédent ; et pour une image personnalisée, il laissait la vignette (périmée) du Store écraser le chemin réel de l'image. Tiley préfère désormais le chemin réel pour les images personnalisées, surveille le fichier du Store et résout à nouveau quand il change, et revérifie deux secondes après chaque notification.

### Supprimé

- Suppression d'un message d'état interne écrit à chaque action de disposition mais jamais affiché dans l'interface (un vestige d'une interface antérieure), ainsi que de ses onze clés de localisation désormais inutilisées dans toutes les langues. Aucun changement de comportement visible.

## [5.2.1] - 2026-07-31

### Corrigé

- Correction : les images de fond mises en cache sont maintenant réduites à la résolution d'aperçu de l'overlay au lieu d'être conservées à la pleine résolution de la photo du bureau. Cela réduit nettement la mémoire résidente et le pic de mémoire lors de l'ouverture de Tiley avec de grands fonds d'écran personnalisés, sans modifier le placement du fond d'écran ni la détection de la couleur de la barre des menus.

## [5.2.0] - 2026-07-31

### Corrigé

- Correction : l'icône de l'application Tiley ressemblait trop à celle du système d'exploitation de bureau le plus répandu.
- Correction : les images de fond mises en cache pour des écrans déconnectés ou reconfigurés pouvaient rester en mémoire jusqu'à ce que la version de l'image du bureau change. Tiley invalide désormais immédiatement le cache des fonds d'écran lors d'un changement de configuration des écrans, ce qui réduit l'usage mémoire inutile après la connexion, la déconnexion ou la réorganisation des moniteurs.
- Correction : après le téléchargement d'une mise à jour, la boîte de dialogue « Installer et relancer » de Sparkle pouvait passer derrière la fenêtre des réglages. Le code qui restaurait la fenêtre des réglages s'exécutait dans le callback `didFinishUpdateCycleFor` de Sparkle, mais ce callback se déclenche dès la fin du cycle de vérification de l'appcast — juste après que l'utilisateur a cliqué sur « Installer la mise à jour » dans la première boîte de dialogue, bien avant que le téléchargement ne se termine et que la boîte de dialogue d'installation/relance n'apparaisse. La fenêtre des réglages revenait donc au premier plan, devant ces boîtes encore actives. La restauration attend désormais `standardUserDriverWillFinishUpdateSession` dès lors que Sparkle a affiché une interface destinée à l'utilisateur ; `didFinishUpdateCycleFor` ne restaure la fenêtre des réglages que pour des vérifications d'arrière-plan vraiment silencieuses, sans aucune boîte de dialogue Sparkle.
- Correction : appliquer une disposition juste après l'ouverture de Tiley pouvait sélectionner les fenêtres dans l'ordre antérieur à l'actualisation. La liste des fenêtres de la barre latérale est d'abord remplie depuis le cache et n'est remplacée qu'à l'arrivée de la capture de référence effectuée en arrière-plan ; un raccourci de préréglage ou un clic dans l'aperçu de disposition déclenché pendant cet intervalle choisissait donc ses cibles dans l'ordre périmé. L'application de la disposition attend désormais la liste de fenêtres actualisée et s'exécute sur celle-ci ; les fenêtres de Tiley sont masquées immédiatement pour que l'interaction reste vive.
- À l'ouverture de Tiley, les fenêtres miniatures de l'aperçu du mini-bureau pouvaient s'afficher brièvement à des positions obsolètes avant de sauter aux bonnes positions une à deux secondes plus tard, une fois la capture asynchrone des fenêtres terminée. La première image est dessinée à partir de la liste de fenêtres en cache, qui ne contient que les coordonnées enregistrées au moment de sa création : les fenêtres déplacées ou redimensionnées pendant que l'interface de Tiley était fermée apparaissaient donc à leur ancienne position. Le réalignement du cache effectué avant l'affichage met désormais aussi à jour les coordonnées (et l'écran hôte) de chaque fenêtre à partir du même instantané rapide CGWindowList déjà utilisé pour l'ordre Z, de sorte que les fenêtres miniatures s'affichent à leur position actuelle dès la première image.

## [5.1.9] - 2026-05-12

### Corrigé

- Correction d'un bug : lorsque l'option « Afficher l'icône dans le Dock » était désactivée, une icône Tiley apparaissait quand même dans le Dock au lancement (sans le point indiquant que l'app est en cours d'exécution). En cause : une scène SwiftUI `Window` cachée qui enregistrait brièvement une fenêtre de 0×32 pt auprès de macOS pendant le démarrage, suffisamment longtemps pour qu'une entrée s'ajoute au Dock avant que la politique `.accessory` ne prenne effet. Cette scène d'ancrage a été supprimée ; la politique d'activation est désormais entièrement pilotée par `applicationWillFinishLaunching` et la logique existante d'`applyDockIconVisibility`.

## [5.1.8] - 2026-05-09

### Corrigé

- Dans les fenêtres groupées dont les bords haut et bas sont alignés, les hauteurs restent désormais alignées lorsqu'on agrandit la hauteur, et plus uniquement lorsqu'on la réduit. Le « setter » de cadre de la fenêtre suiveuse appliquait d'abord la taille puis la position ; un agrandissement qui aurait fait dépasser le bord supérieur derrière la barre des menus ou le bord d'écran était silencieusement plafonné par l'app — le bas suivait le drag, mais le haut dérivait vers le bas. Le setter pré-positionne maintenant la suiveuse à son emplacement final prévu avant d'appliquer la nouvelle taille ; une correction finale de position basée sur la taille réellement acceptée par l'app maintient le bord de contact stable, même quand des contraintes min/max entrent en jeu. Au relâchement du drag, une passe de « snap » finale recale les bords haut/bas (ou gauche/droite) que le cache considérait comme alignés sur ceux de la source, supprimant ainsi les décalages résiduels de quelques pixels.

## [5.1.7] - 2026-05-08

### Supprimé

- Le chemin de repli qui remplissait le fond des mini-écrans de la grille de disposition avec le cache BMP de l'agent de fond d'écran, pour les types de fond sans vignette dédiée (photothèque, Aerial, etc.), a été supprimé. Ce cache, situé dans le conteneur de `com.apple.wallpaper.agent` (`~/Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches/`), déclenche sous macOS Sequoia la nouvelle invite d'autorisation « Données d'app », ce qui est une demande disproportionnée pour une image d'arrière-plan purement décorative. Tiley s'appuie désormais uniquement sur l'URL publique du fond d'écran et sur `/System/Library/Desktop Pictures/.thumbnails/` ; lorsque ni l'une ni l'autre de ces sources ne résout le fond, l'image est simplement omise et la grille, la couleur de remplissage et la disposition de l'écran continuent à s'afficher.

## [5.1.6] - 2026-05-08

### Corrigé

- Au premier lancement sur un Mac neuf, plus aucune boîte de dialogue d'autorisation parasite "Réception des frappes" (Surveillance de l'entrée) ne s'affiche. Cette boîte apparaissait parce que Tiley créait un `CGEventTap` pour surveiller les clics de souris avant l'octroi de l'Accessibilité ; le tap est désormais créé de manière différée, au moment précis où l'Accessibilité passe à accordée, ce qui amène macOS à considérer la création du tap comme couverte par l'autorisation d'Accessibilité et à omettre entièrement l'invite de Surveillance de l'entrée.
- Après avoir accordé l'Accessibilité pour la première fois et être revenu sur Tiley, la liste des fenêtres de la barre latérale et la grille de disposition se remplissent désormais immédiatement au lieu de rester bloquées sur "Aucune fenêtre". Le cache de la liste des fenêtres était auparavant rempli avec un résultat vide tant que l'Accessibilité manquait, puis traité comme faisant autorité une fois l'autorisation accordée ; le rafraîchissement du cache est désormais ignoré sans Accessibilité, et le chemin de retour après l'octroi active explicitement la grille de disposition et déclenche une nouvelle capture.

## [5.1.5] - 2026-05-08

### Corrigé

- Le badge de groupement de fenêtres (le cercle flottant affiché entre les fenêtres liées) ne survole plus les feuilles ni les dialogues modaux présentés par la même application. La détection couvre les sous-rôles de la fenêtre focalisée `AXDialog` / `AXSystemDialog`, le rôle `AXSheet` et les fenêtres parentes avec une feuille attachée ; tant que l'un d'eux est affiché, le badge est masqué et réapparaît une fois le modal fermé.

## [5.1.4] - 2026-05-03

### Corrigé

- Après avoir explicitement dégroupé deux fenêtres, les avoir éloignées puis remises bord à bord, le badge candidat « former un groupe » réapparaît à nouveau. Auparavant, le dégroupage arrêtait l'observation d'Accessibilité des fenêtres devenues isolées, de sorte que leurs déplacements manuels ultérieurs ne déclenchaient plus les événements qui pilotent la détection d'adjacence — le badge ne réapparaissait silencieusement plus jusqu'à ce qu'un autre événement (changement de Space, activation d'une app, etc.) déclenche à nouveau le rafraîchissement du cache de liste de fenêtres.

## [5.1.3] - 2026-04-27

### Corrigé

- La fenêtre des Réglages s'ouvre désormais centrée sur l'écran entier, et non plus au centre de la zone visible excluant le Dock : elle apparaît au véritable centre de l'écran quelle que soit la position du Dock.

## [5.1.2] - 2026-04-26

### Corrigé

- Plus aucun badge candidat « Créer un groupe » n'apparaît entre des fenêtres déjà liées — qu'il s'agisse de paires devenues adjacentes par hasard après l'application d'un préréglage, de paires appartenant à deux groupes existants distincts, ou de paires déjà connectées via le mécanisme de satellite des préréglages avec applications assignées.
- Les badges des groupes liés ne sont désormais affichés que pour le groupe contenant la fenêtre au premier plan (ou relié à elle via les satellites). Les badges des groupes d'arrière-plan sans rapport, qui partageaient simplement l'application de la fenêtre focalisée, ont disparu.
- Mettre une fenêtre groupée au premier plan — par clic, par sélection dans la barre latérale de Tiley puis Entrée, ou via le clic-pour-activer de macOS — amène désormais l'ensemble du groupe en avant de manière fiable. Plusieurs cas où une fenêtre sœur du groupe restait derrière une autre fenêtre sont corrigés (fenêtres d'une autre application coincées entre des membres du groupe, l'application réascendant la précédente fenêtre principale plutôt que la fenêtre sélectionnée, et l'animation de restauration des décalages hors écran de Tiley elle-même qui était confondue avec un glissement manuel).

### Modifié

- L'application d'une préréglage de mise en page dont la paire groupée cible une fenêtre déjà membre d'un groupe existant ne fusionne plus tout en un seul grand groupe. La fenêtre partagée devient une « ancre de fenêtre » et chacun de ses partenaires (les autres membres du groupe préexistant et le partenaire nouvellement ajouté) est enregistré comme satellite, reflétant le modèle déjà utilisé pour les emplacements de préréglage assignés à une application. Chaque paire conserve sa propre disposition mémorisée : cliquer sur un satellite ramène l'ancre au premier plan et restaure les positions sauvegardées de cette paire ; cliquer sur l'ancre fait passer en paire active le satellite actuellement le plus au premier plan. Exemple : avec un groupe A↔B existant, appliquer un préréglage qui appaire C↔A laisse A↔B intact — cliquer sur B ramène A à côté de B dans la disposition originale A↔B ; cliquer sur C place A à côté de C selon la disposition C↔A du préréglage. La paire active affiche le badge de liaison comme avant ; basculer entre satellites reconstruit dynamiquement le groupe spatial

## [5.1.1] - 2026-04-25

### Ajouté

- Le menu au survol du badge de lien d'un groupe de fenêtres comporte désormais un troisième bouton à côté de celui de permutation : **Aligner la hauteur des fenêtres** (pour les paires gauche/droite, icône flèches haut/bas) ou **Aligner la largeur des fenêtres** (pour les paires haut/bas, icône flèches gauche/droite). Il aligne les deux côtés du badge (tous les membres du groupe, classés par la ligne de contact) sur l'axe perpendiculaire. « Les deux côtés » désigne non seulement les deux fenêtres directement reliées par le badge, mais aussi **tous les membres du groupe situés du même côté de la ligne de contact** — y compris les « sœurs » qui ne sont pas directement reliées entre elles mais partagent un bord parent (exemple : `[A]` en haut, `[B]` et `[C]` touchant chacune le bord inférieur de A sans être reliées entre elles → cliquer sur « Aligner la largeur » sur le badge A↔B traite `{B, C}` comme un seul côté et B+C réunies prennent la même largeur que A). À l'intérieur de chaque côté, les fenêtres sont triées et reposées bord à bord : les bords extrêmes sont ancrés à l'enveloppe extérieure et les fenêtres adjacentes se rejoignent au milieu de leurs bords d'origine, donc les bords communs déjà alignés restent en place tandis qu'un écart ou un chevauchement est réparti à parts égales entre les deux fenêtres. Le bouton est masqué quand les deux côtés sont déjà alignés et qu'il n'y a aucun écart ou chevauchement interne à corriger
- Les badges candidats « former un groupe » apparaissent désormais aussi lorsque vous déplacez ou redimensionnez manuellement une fenêtre de sorte que son bord touche celui d'une autre fenêtre — pas seulement après l'application d'une mise en page Tiley. Le badge apparaît au moment où vous relâchez la souris (il reste masqué pendant le déplacement/redimensionnement lui-même), et un clic dessus relie la paire en un groupe de fenêtres exactement comme le badge candidat après application d'une mise en page
- Cliquer sur un badge candidat « former un groupe » fait apparaître immédiatement le menu de survol (Dissocier / Permuter / Aligner la hauteur ou la largeur) au moment même où le groupe est établi — plus besoin de sortir le curseur du badge puis d'y revenir
- Le menu de survol (la pilule d'actions) apparaît et disparaît désormais en fondu enchaîné au lieu de s'afficher et de se masquer brusquement. Pendant le fondu de sortie, le panneau du badge conserve sa taille étendue pour que la pilule ne soit pas coupée ; un re-survol pendant l'animation annule la rétraction
- Deux nouveaux boutons dans le menu de survol du badge lié : **Occuper la largeur de l'écran** (icône `rectangle.portrait.arrowtriangle.2.outward`) et **Occuper la hauteur de l'écran** (icône `rectangle.arrowtriangle.2.outward`). Ils mettent à l'échelle proportionnellement toutes les fenêtres du groupe pour que son rectangle englobant épouse exactement la largeur ou la hauteur de la zone visible de l'écran (Dock et barre de menus exclus), tout en préservant l'espacement relatif entre les membres. Chaque bouton est masqué quand le groupe occupe déjà l'écran sur cet axe
- En survolant le badge de lien entre deux fenêtres réelles regroupées, un petit menu d'actions apparaît désormais sous le badge (ou au-dessus, si l'espace en bas est insuffisant) : un bouton **Dissocier** et un bouton pour permuter les fenêtres — **Permuter les fenêtres gauche/droite** ou **Permuter les fenêtres haut/bas** selon la disposition de la paire. Le badge lui-même ne se transforme plus en bouton de dissociation ; il sert uniquement d'indicateur visuel du lien. La permutation supprime également tous les autres liens que ces deux fenêtres pourraient avoir avec d'autres fenêtres, ne laissant qu'un groupe propre composé uniquement de la paire permutée

### Corrigé

- Lors de l'application d'un preset de mise en page multi-rectangles, si une fenêtre ne peut pas se réduire à son rectangle cible en raison de la taille minimale imposée par l'application, la largeur ou la hauteur de la fenêtre voisine est désormais ajustée automatiquement afin que le bord partagé reste aligné (l'écart du preset est préservé). Auparavant, cela provoquait des chevauchements ou des écarts mal alignés
- L'indicateur de regroupement de la barre latérale affiche désormais aussi les liens satellites de slot d'application qui ne font pas partie du groupe spatial actuellement actif. Quand un preset contenant des rectangles assignés à des applications et des paires regroupées est appliqué, la fenêtre du côté non assigné est enregistrée comme satellite du bundle ID de l'application assignée. Si l'on réapplique le preset (ou un autre preset avec la même application d'ancrage) en utilisant une autre fenêtre, la paire précédente sort du `WindowGroup` spatial, mais son lien satellite (la liaison de mise au premier plan au clic) est conservé. Jusqu'à présent, ces liens « en arrière-plan mais toujours actifs » n'apparaissaient pas dans la barre latérale ; ils sont désormais affichés à côté des partenaires spatiaux actifs sous forme d'icônes d'application partenaire, et chacun peut être délié individuellement via la même interaction survol → clic. Cela vaut aussi quand une même fenêtre est satellite de plusieurs applications d'ancrage, ou quand un même bundle de fenêtre d'ancrage a plusieurs satellites enregistrés

### Modifié

- Lors de l'application d'un préréglage de disposition qui colle une fenêtre contre un bord d'écran, seules les adjacences de groupe situées du côté de la fenêtre redimensionnée qui touche le bord de l'écran sont désormais rompues — les adjacences sur les autres bords sont conservées. Par exemple, avec une paire horizontale A↔B et une paire verticale A↔C, appliquer « Remplir la largeur de l'écran » à A rompt le lien A↔B (le bord droit de A devient le bord droit de l'écran), mais le lien A↔C est préservé tant que le bord inférieur de A n'atteint pas le bord inférieur de l'écran. Auparavant, tout redimensionnement par Tiley n'affectant qu'une partie d'un groupe dissolvait le groupe entier, quels que soient les bords concernés
- L'indicateur de regroupement de la barre latérale a été repensé. Au lieu d'un badge de lien flottant entre les lignes, chaque ligne de fenêtre regroupée affiche maintenant à droite — juste avant le badge d'index — les icônes des applications de toutes ses fenêtres partenaires liées, alignées côte à côte. Le survol d'une icône partenaire met en surbrillance la ligne de la fenêtre partenaire dans la barre latérale, et fait simultanément basculer cette icône (ainsi que l'icône correspondante dans la ligne partenaire) dans un état rouge `x`, ce qui permet de voir d'un coup d'œil quelles deux fenêtres sont concernées. Un clic à l'état `x` ne défait que ce lien-là ; ainsi, lorsqu'une fenêtre est liée à plusieurs autres, les liens peuvent être défaits un par un. L'emplacement du badge d'index est toujours réservé, afin que les lignes restent alignées même lorsqu'aucun index n'est affiché

## [5.1.0] - 2026-04-25

### Ajouté

- Nouveau préréglage de disposition par défaut « Centre » : une grille 4×4 avec la zone centrale 2×2 sélectionnée, associé au raccourci `C`
- Nouvelle ligne « + » à la fin de la liste des préréglages de disposition. Cliquer dessus crée un préréglage nommé « Nouveau préréglage de disposition » et passe immédiatement en mode édition
- Le regroupement peut désormais être défini directement lors de l'édition d'un préréglage : un badge `link.badge.plus` apparaît à chaque bord partagé entre deux zones du préréglage ; cliquez pour marquer la paire comme groupée (le badge passe en état lié ; le survol fait apparaître l'icône de suppression). Lorsque le pointeur survole un préréglage dans la barre latérale, les badges liés s'affichent également sur l'aperçu afin de voir d'un coup d'œil quelles zones seront groupées. À l'application du préréglage, les fenêtres correspondantes sont regroupées dès le départ, sans clic supplémentaire
- Les rectangles d'un préréglage de disposition peuvent désormais être liés à une application spécifique. Dans l'éditeur de préréglages, chaque rectangle affiche un badge `macwindow.badge.plus` : cliquez pour choisir une application en cours d'exécution (ou parcourez le système de fichiers via « Autre application… »). Les rectangles attribués s'affichent comme une fenêtre miniature avec l'icône de l'application au lieu d'un numéro ; survolez l'icône et cliquez dessus pour retirer l'attribution. À l'application du préréglage, un rectangle attribué reçoit toujours la fenêtre au premier plan de l'application liée (avec lancement automatique et attente jusqu'à 30 s si besoin). Si l'application est lancée mais n'a aucune fenêtre, une notification système est affichée. Lorsqu'une paire groupée a exactement un côté attribué, la fenêtre qui atterrit côté non attribué est liée à la fenêtre de l'application comme « satellite » pour la durée de la session : un clic sur l'une fait aussi passer l'autre au premier plan

### Modifié

- `debugLog` utilise désormais `@autoclosure` : lorsque la journalisation de débogage est désactivée, l'interpolation des chaînes des messages de journal n'entraîne plus aucun coût

### Corrigé

- Les badges de lien de groupement de fenêtres n'apparaissent plus sur les fenêtres entièrement masquées derrière une autre fenêtre. Après l'application d'une disposition à de nombreuses fenêtres, les badges ne s'affichent qu'entre les fenêtres visibles (au premier plan) ; les fenêtres occultées sont exclues des candidats au groupement jusqu'à ce qu'elles soient ramenées au premier plan

### Supprimé

- Suppression du préréglage temporaire « Dernière sélection » qui était automatiquement ajouté après l'application d'une disposition. Les nouveaux préréglages se créent désormais explicitement via la ligne « + »

## [5.0.1] - 2026-04-23

### Corrigé

- Corrigé un scintillement des fenêtres groupées lors du retour à leur app via Cmd+Tab. La liaison d'ordre Z pouvait se déclencher avant que macOS ait fini de remonter les fenêtres de l'app, faisant apparaître brièvement un membre du groupe non focalisé devant celui qui avait le focus

## [5.0.0] - 2026-04-22

### Ajouté

- Ajout du regroupement de fenêtres. Après l'application d'un préréglage de disposition contenant plusieurs fenêtres, un badge de lien (`link.badge.plus`) apparaît au milieu de chaque bord en contact. Cliquer sur le badge regroupe les fenêtres : faire glisser une fenêtre déplace tous les membres ensemble, redimensionner le bord commun redimensionne la fenêtre voisine en sens inverse et mettre un membre au premier plan élève les autres juste en dessous. Un survol du badge révèle une icône permettant de dissoudre le groupe ; fermer l'une des fenêtres du groupe le dissout également automatiquement
- Badge de lien dans la barre latérale : dans la barre latérale de la fenêtre principale, un petit indicateur de lien apparaît désormais entre deux lignes consécutives de fenêtres groupées, permettant de voir d'un coup d'œil quelles fenêtres sont associées. Si une fenêtre groupée risquait d'être séparée de sa partenaire par un bloc d'en-tête d'application, elle est extraite de ce bloc et placée directement sous sa partenaire afin que le lien reste visible

### Corrigé

- Correction des aperçus au survol et au glissement sur la grille de la fenêtre principale qui utilisaient le style de rectangle de la modification de préréglage (rempli teinté, sans barre de titre) également lors de l'application normale d'une disposition ; en dehors de la modification d'un préréglage, la fenêtre miniature avec icône de l'application, nom de l'application et titre de la fenêtre est désormais correctement affichée
- Correction du positionnement incorrect occasionnel de l'une des deux fenêtres lors de l'application d'une disposition côte à côte à une sélection multiple. L'animation qui écartait temporairement les fenêtres masquant la fenêtre sélectionnée continuait de s'exécuter après l'application de la disposition et écrasait les positions finales
- Correction d'une fenêtre pouvant dériver lentement vers le coin inférieur droit après l'application d'une disposition côte à côte. Le nettoyage différé qui suit le masquage de la fenêtre principale pouvait démarrer une animation de restauration alors que la fenêtre tout juste placée figurait encore dans la liste des fenêtres écartées, la ramenant progressivement vers sa position antérieure au déplacement

## [4.4.3] - 2026-04-20

### Modifié

- Lors de la modification d'un préréglage de disposition, les aperçus au survol et lors du glissement sur la grille utilisent désormais le même style de rectangle que les sélections validées : teintés avec la couleur du prochain index et affichant en son centre le numéro d'index à attribuer, sans barre de titre ni bouton de suppression. De plus, le survol d'une cellule vide affiche un aperçu de rectangle d'une cellule même si d'autres dispositions sont déjà enregistrées
- Lors de la modification d'un préréglage, le rectangle au survol et le rectangle de glissement affichent désormais au centre le numéro d'index qui sera attribué à la validation (avec la même apparence que le rectangle validé), y compris l'aperçu d'une seule cellule au survol. Les aperçus des préréglages de disposition (survol d'un préréglage dans la barre latérale, superposition d'aperçu plein écran lors de l'application de préréglages à sélections multiples) continuent également d'afficher les numéros d'index

### Corrigé

- Correction du saut de la fenêtre principale vers le centre de l'écran lors de l'ajout ou de la modification d'une grille dans un préréglage de disposition lorsque « Afficher près de l'icône au clic » était activé ; la fenêtre reste désormais ancrée près de l'icône de la barre de menus
- Correction du fait que les rectangles de sélection validés s'affichaient parfois sans remplissage ni bordure (avec uniquement le bouton de fermeture et l'étiquette de numéro visibles) lorsqu'un préréglage de disposition contenait plusieurs sélections

## [4.4.2] - 2026-04-19

### Corrigé

- Correction de l'ordre de superposition inversé lors de l'application d'une disposition à plusieurs fenêtres sélectionnées ; la première fenêtre sélectionnée (principale) passe désormais au premier plan comme prévu

## [4.4.1] - 2026-04-18

### Modifié

- Lors de l'ouverture par raccourci, l'aperçu de l'écran miniature – et non la fenêtre entière – est désormais centré sur l'écran. La référence est le cadre complet de l'écran (avec la barre de menus et le Dock), de sorte que la miniature reste centrée même lorsque le Dock est à gauche ou à droite
- Lorsque « Afficher près de l'icône au clic » est activé, cliquer sur l'icône de la barre de menus aligne désormais le centre de l'aperçu miniature (et non celui de la fenêtre entière) sur l'icône ; le triangle de la bulle pointe toujours directement vers l'icône

## [4.4.0] - 2026-04-17

### Modifié

- Amélioration des aperçus de fenêtres miniatures sur la grille : le survol et le glissement affichent désormais des fenêtres miniatures teintées au lieu de rectangles de couleur unie, les écrans secondaires affichent le même style de fenêtre miniature que l'écran principal, et les cellules de la grille restent visibles pendant le glissement
- Simplification de la superposition sur les écrans non ciblés : suppression de l'icône de disposition miniature des écrans, affichage d'une grande flèche directionnelle centrée uniquement
- Les interactions de grille sur les fenêtres d'écrans secondaires répondent désormais au premier clic sans nécessiter un clic supplémentaire pour obtenir le focus

### Corrigé

- Correction du triangle de bulle qui disparaissait et de la fenêtre qui se décalait vers le haut avant l'animation de fondu lors de la fermeture de Tiley en cliquant sur l'icône de la barre de menus. Le triangle reste désormais visible pendant le fondu, comme lors de la fermeture en cliquant sur une autre fenêtre
- Correction du triangle de bulle qui s'affichait incorrectement sur les fenêtres des écrans secondaires lors de l'ouverture de Tiley depuis l'icône de la barre de menus
- Correction des boutons de la barre d'outils désactivés au démarrage lorsque la liste des fenêtres était déjà disponible avant l'apparition de la barre latérale

## [4.3.9] - 2026-04-14

### Ajouté

- Ajout d'un pointeur triangulaire façon bulle de dialogue sur le bord de la fenêtre principale orienté vers l'icône de la barre de menus ou du Dock lorsque « Afficher près de l'icône au clic » est activé

### Corrigé

- Correction d'un problème où, en ouvrant Tiley juste après avoir changé d'app et avant que le cache de la liste de fenêtres en arrière-plan soit rafraîchi, la barre latérale affichait brièvement l'app précédemment au premier plan en haut, ou sélectionnait parfois une fenêtre qui n'était pas au premier plan

## [4.3.8] - 2026-04-13

### Ajouté

- Animation fluide de fondu en entrée/sortie lors de l'affichage et du masquage de la fenêtre superposée grâce à Core Animation accélérée par GPU

### Corrigé

- Les boutons de la barre d'outils étaient désactivés au premier lancement tant que la sélection de fenêtre n'était pas modifiée dans la barre latérale

## [4.3.7] - 2026-04-10

### Modifié

- Amélioration significative de la vitesse d'ouverture de la fenêtre superposée. Les opérations lourdes (requêtes Accessibility/CoreGraphics, construction de l'aperçu de disposition) sont différées après l'affichage de la fenêtre, et la liste de fenêtres pré-mise en cache est conservée entre les sessions

## [4.3.6] - 2026-04-10

### Ajouté

- Ajout d'une option pour afficher la fenêtre Tiley près de l'icône de la barre de menus ou du Dock au clic (activée par défaut)

## [4.3.5] - 2026-04-09

### Corrigé

- Correction de l'incohérence du rayon d'angle de la fenêtre miniature sur le mini-écran lors des aperçus de survol et de glissement pour correspondre à la fenêtre sélectionnée

## [4.3.4] - 2026-04-09

### Corrigé

- Fermeture de la fenêtre des réglages avant la vérification des mises à jour Sparkle afin que l'aperçu de la grille au survol ne la ramène pas au premier plan et ne masque pas les dialogues Sparkle. La fenêtre des réglages est restaurée à la fin du cycle de mise à jour

## [4.3.3] - 2026-04-09

### Ajouté

- La fenêtre peut désormais être déplacée en faisant glisser la barre d'indices clavier, les zones barre de menus/Dock du mini-écran, les zones vides de la barre latérale et les espaces entre les boutons de la barre d'outils

### Corrigé

- Le glissement dans la partie supérieure de la grille déplaçait la fenêtre au lieu de sélectionner des cellules

## [4.3.2] - 2026-04-08

### Corrigé

- Correction d'un bug où deux fenêtres pouvaient être sélectionnées en invoquant Tiley juste après avoir changé de fenêtre

## [4.3.1] - 2026-04-07

### Corrigé

- Masquage de la fenêtre des réglages lorsque Sparkle affiche la boîte de dialogue de mise à jour, empêchant l'aperçu de la grille au survol de ramener la fenêtre des réglages au premier plan et de bloquer le bouton « Installer et redémarrer »

## [4.3.0] - 2026-04-07

### Modifié

- La recherche dans la barre latérale utilise désormais la correspondance par sous-séquence — taper « f1 » correspond à « Finder Users1 » même avec des caractères non consécutifs
- La recherche dans la barre latérale inclut également le nom original (non localisé) de l'app, ainsi « ai » correspond à « Mail » même si l'app est affichée avec un nom localisé

### Corrigé

- Correction d'un problème où la fermeture d'une fenêtre entraînait parfois une sélection multiple involontaire des fenêtres suivantes dans la barre latérale
- Correction d'un problème où la fenêtre miniature sur la grille ne se mettait pas à jour vers la nouvelle cible après la fermeture d'une fenêtre

## [4.2.3] - 2026-04-05

### Ajouté

- Le menu contextuel inclut désormais « Fermer N fenêtres » lorsque plusieurs fenêtres sont sélectionnées ; les apps n'ayant qu'une seule fenêtre sont quittées au lieu de simplement fermer la fenêtre, et la sélection est réinitialisée à une seule fenêtre après la fermeture

### Modifié

- Le survol d'une cellule de la grille affiche désormais un aperçu de fenêtre miniature avec l'icône de l'application et la barre de titre, au lieu d'un simple rectangle bleu, harmonisant l'apparence avec la sélection par glisser
- Après la fermeture d'une fenêtre via le menu contextuel ou la touche « / », la barre latérale sélectionne désormais l'élément situé en dessous de la fenêtre fermée ; s'il n'y a pas d'élément en dessous, l'élément au-dessus est sélectionné

### Corrigé

- Les fenêtres déplacées (non ciblées) reviennent désormais correctement à leur position d'origine après l'application d'une disposition multi-fenêtres
- « Dernière sélection » s'affiche désormais correctement même lorsque sa disposition principale correspond à un préréglage comportant des dispositions secondaires (par exemple, la sélection manuelle de la moitié supérieure n'est plus masquée par le préréglage « Moitié supérieure » qui inclut également une disposition secondaire pour la moitié inférieure)
- L'aperçu de la grille ne s'affichait pas au survol de la section Grille dans les Réglages
- L'aperçu de la grille ne se mettait pas à jour en temps réel lors de la modification des valeurs de lignes, colonnes ou espacement dans les Réglages
- Les états « Afficher le bureau » et Mission Control sont automatiquement désactivés lors de l'appel de Tiley via le raccourci global ou l'icône de la barre des menus
- La fenêtre de superposition de Tiley n'apparaît plus dans Mission Control / Exposé

## [4.2.2] - 2026-04-04

### Modifié

- Les fenêtres de superposition sont désormais pré-rendues avec une opacité nulle et maintenues à l'écran, de sorte que l'affichage de la grille de disposition ne nécessite qu'un changement d'alpha — réduisant considérablement la latence perçue
- La fenêtre des réglages se ferme désormais automatiquement lorsque l'utilisateur clique sur une autre application ; Tiley reste masqué jusqu'à ce que le raccourci global soit utilisé à nouveau

### Corrigé

- Correction du clic sur l'icône du Dock affichant « Aucune fenêtre » au lieu des réglages lorsque la fenêtre des réglages était ouverte
- Correction de la fenêtre des réglages disparaissant définitivement lors de la désactivation de « Afficher l'icône du Dock »
- Correction du raccourci global ne fonctionnant plus après que la fenêtre des réglages a perdu le focus au profit d'une autre application

## [4.2.1] - 2026-04-04

### Modifié

- Ajout d'un indicateur chevron au bouton de redimensionnement pour indiquer clairement qu'il ouvre un menu déroulant
- Amélioration du timing de l'action de redimensionnement pour que la fenêtre Tiley disparaisse avant le redimensionnement de la fenêtre cible, rendant l'interaction plus intuitive

## [4.2.0] - 2026-04-04

### Ajouté

- Redimensionner les fenêtres à des tailles prédéfinies (16:9, 16:10, 4:3, 9:16) depuis le bouton de la barre d'outils ou le menu contextuel ; les tailles dépassant l'écran actuel sont automatiquement exclues
- Aperçu en direct au survol des éléments du menu de redimensionnement : superposition taille réelle sur l'écran cible et aperçu miniature sur la grille (même style que l'aperçu des dispositions prédéfinies)
- Aperçu de fenêtre miniature (avec barre de titre et icône d'app) affiché pendant la sélection par glisser sur la grille

## [4.1.2] - 2026-04-03

### Ajouté

- Badges d'index d'ordre de sélection affichés à droite des éléments de fenêtre dans la barre latérale lorsque deux fenêtres ou plus sont sélectionnées

### Modifié

- La liste des fenêtres dans la barre latérale est désormais pré-mise en cache en arrière-plan via des écouteurs d'événements de l'espace de travail (activation, lancement et fermeture d'applications), et s'affiche instantanément à l'ouverture de la superposition
- Amélioration du comportement de mise en surbrillance des éléments groupés par application dans la barre latérale. L'en-tête de l'application n'est affiché comme sélectionné que lorsque toutes ses fenêtres sont sélectionnées, et le survol de l'en-tête met en surbrillance à la fois l'en-tête et toutes ses fenêtres enfants
- Amélioration du comportement de sortie du plein écran : définit désormais l'attribut AXFullScreen directement (avec appui sur le bouton en secours), en attendant jusqu'à 2 secondes la fin de l'animation

### Corrigé

- Correction du problème où l'overlay ne s'ouvrait pas lorsque l'application au premier plan n'a pas de fenêtres. Un message « Aucune fenêtre » est affiché et le glisser est désactivé
- Correction du bureau du Finder traité comme une fenêtre redimensionnable. Lorsque le bureau est au premier plan, la fenêtre réelle du Finder la plus en avant est ciblée, ou « Aucune fenêtre » est affiché s'il n'en existe aucune
- Correction d'un problème où l'overlay ne s'ouvrait pas lorsque l'application au premier plan n'a pas de fenêtre (par exemple, Finder sans fenêtre ouverte, applications uniquement dans la barre de menus) ; utilise maintenant la fenêtre visible la plus en avant sur l'écran
- Correction d'un problème où la position de la fenêtre n'était pas correctement appliquée sur les écrans non principaux pour certaines applications (ex. Notion). Ajout d'une vérification de position avec tentatives de réessai après le redimensionnement pour gérer les applications qui réinitialisent la position de manière asynchrone

## [4.1.1] - 2026-03-31

### Modifié

- Le raccourci par défaut pour sélectionner la fenêtre suivante est passé de Tab à Space ; la fenêtre précédente est passée de Shift+Tab à Shift+Space
- Les fenêtres déplacées reviennent désormais toujours à leur position d'origine avec une animation lors de la fermeture de la superposition

## [4.1.0] - 2026-03-31

### Ajouté

- Changement de fenêtre en maintenant les touches de modification (style Cmd+Tab) : après avoir ouvert le panneau, maintenez les touches de modification et appuyez sur la touche de déclenchement pour parcourir les fenêtres ; relâchez les touches de modification pour mettre la fenêtre sélectionnée au premier plan ; appuyez sur un raccourci local de disposition tout en maintenant les touches de modification pour appliquer la disposition
- Section de remerciements pour les licences tierces dans les Réglages (Sparkle, TelemetryDeck)

### Modifié

- Les panneaux Réglages et Autorisations sont désormais des fenêtres indépendantes au niveau normal (non flottant), permettant aux dialogues de mise à jour Sparkle et autres fenêtres système de s'afficher au-dessus
- La barre latérale est désormais toujours visible ; le bouton d'affichage/masquage a été supprimé
- Le bouton des réglages a été déplacé de la barre inférieure vers l'extrémité gauche de la barre d'actions de la barre latérale
- L'aperçu mini-écran a désormais des coins arrondis sur les quatre côtés quel que soit le type d'écran
- La barre de titre de la fenêtre miniature affiche désormais le nom de l'application en plus du titre de la fenêtre
- Le badge « Mise à jour disponible » a été remplacé par un point rouge sur le bouton des réglages et une infobulle ; dans le panneau des réglages, un popover s'affiche sur le bouton « Vérifier les mises à jour »

## [4.0.9] - 2026-03-30

### Corrigé

- Le redimensionnement de fenêtre échouait et la position était décalée pour certaines applications : la position de rebond lorsque le redimensionnement initial était rejeté se trouvait en bas de l'écran (pas d'espace pour s'agrandir), laissant la fenêtre à une position incorrecte. Le rebond se fait désormais vers le haut de la zone visible et la position est explicitement restaurée si le redimensionnement échoue toujours
- Les fenêtres déplacées n'étaient parfois pas restaurées à leur position d'origine après la sélection d'une fenêtre en arrière-plan : la restauration recherchait les fenêtres dans une liste potentiellement obsolète, entraînant des échecs. Les références de fenêtre sont désormais stockées directement dans les données de suivi de déplacement, et le nettoyage est différé jusqu'à la fin de l'animation de restauration
- Les boutons « Ajouter un raccourci » / « Ajouter un raccourci global » ne répondaient qu'aux clics près du centre : le remplissage et l'arrière-plan ont été déplacés à l'intérieur du label du bouton afin que toute la zone visible soit cliquable

## [4.0.8] - 2026-03-30

### Corrigé

- Le panneau des autorisations n'est plus affiché au-dessus des autres applications et des fenêtres système lors de la demande d'accès à l'accessibilité
- L'aperçu du fond d'écran ne s'affichait pas sous macOS Tahoe 26.4 : adaptation au changement de structure du plist du Store de fonds d'écran (`Desktop` → clé `Linked`), les fonds d'écran Photos sont chargés depuis le cache BMP de l'agent de fonds d'écran, ajout de la valeur de placement `FillScreen` (remplacement de `Stretch` sous Tahoe), et activation des paramètres de mode d'affichage pour les fournisseurs de fonds d'écran non système
- Les modes d'affichage centré et mosaïque affichaient les images trop petites lorsque les métadonnées DPI de l'image n'étaient pas 72 (par ex. captures d'écran Retina à 144 DPI) ; les dimensions réelles en pixels sont désormais toujours utilisées

## [4.0.7] - 2026-03-29

### Corrigé

- Le mode d'affichage mosaïque du fond d'écran n'était pas reflété dans l'aperçu du mini-écran (la valeur de placement « Tiled » du plist du Store de fonds d'écran macOS n'était pas correctement reconnue)
- Ajout de journaux de débogage pour le pipeline de résolution du fond d'écran afin d'aider au diagnostic des problèmes d'affichage

## [4.0.6] - 2026-03-29

### Ajouté

- Le survol d’un preset multi-disposition affiche désormais les numéros d’index de disposition sur la grille mini-écran, l’aperçu en taille réelle et la liste des fenêtres de la barre latérale, permettant d’identifier intuitivement quelle disposition s’applique à chaque fenêtre indépendamment de la perception des couleurs

### Modifié

- Interface de la fenêtre de réglages affinée pour correspondre au look & feel de macOS Tahoe : boutons de la barre d'outils et de la barre d'actions unifiés en forme de capsule avec des fonds de survol/pression adaptatifs au système, cartes de section de réglages avec fond gris clair sans bordure, boutons bascule redimensionnés à la taille de Préférences Système, et liste des raccourcis restructurée avec une section indépendante « Raccourcis déplacer vers l'écran »

### Corrigé

- Les fenêtres de la barre latérale dépassant le nombre de dispositions du preset affichent désormais correctement la couleur de la dernière disposition au lieu de la couleur de sélection principale

## [4.0.5] - 2026-03-29

### Corrigé

- Les fenêtres déplacées pour afficher la fenêtre cible sélectionnée reviennent désormais correctement à leur position d'origine, même lors d'un changement rapide de cible
- L'aperçu de redimensionnement d'une seule fenêtre était trop pâle par rapport aux aperçus de disposition multi-fenêtres ; utilise désormais la même opacité

## [4.0.4] - 2026-03-29

### Ajouté

- Au survol d'un preset, l'aperçu du mini-écran affiche les barres de titre des fenêtres (icône d'app, nom d'app, titre de fenêtre)

### Modifié

- La barre de titre de l'aperçu de disposition en taille réelle affiche désormais le nom de l'app avec le titre de la fenêtre (format : « Nom de l'App — Titre de la Fenêtre »)

## [4.0.3] - 2026-03-29

### Ajouté

- Les presets multi-disposition redimensionnent maintenant plusieurs fenêtres même avec une seule fenêtre sélectionnée, en utilisant l'ordre Z réel (fenêtre la plus en avant en premier)
- Lorsque les fenêtres sélectionnées sont moins nombreuses que les définitions de disposition, la fenêtre sélectionnée est toujours traitée comme principale et les emplacements restants sont remplis par ordre Z
- Au survol d'un preset multi-disposition, les lignes des fenêtres concernées dans la barre latérale sont mises en surbrillance avec les couleurs de disposition (bleu, vert, orange, violet)

## [4.0.2] - 2026-03-29

### Modifié

- L'aperçu de disposition en taille réelle n'affiche désormais que les aperçus correspondant au nombre de sélections définies dans le préréglage (les fenêtres sélectionnées au-delà du nombre de sélections du préréglage ne sont plus affichées)

## [4.0.1] - 2026-03-29

### Modifié

- La palette de couleurs de sélection cycle désormais entre bleu, vert, orange et violet (4 couleurs), la 5e sélection ayant la même couleur que la 1re
- Les préréglages par défaut (Moitié gauche/droite/haute/basse) incluent désormais la moitié opposée comme sélection secondaire

## [4.0.0] - 2026-03-29

### Ajouté

- Préréglages de disposition à sélection multiple : définissez plusieurs zones de grille par préréglage pour positionner différentes fenêtres à différents emplacements
  - Chaque glisser dans l'éditeur de préréglages ajoute une nouvelle sélection (1ère, 2ème, 3ème, ...)
  - Chaque sélection affiche son numéro d'index et un bouton de suppression
  - Le chevauchement des sélections est empêché (avec retour visuel)
  - Lors de l'application d'un préréglage à sélection multiple, les fenêtres sont assignées par ordre de sélection : la première fenêtre sélectionnée reçoit la sélection 1, la suivante la sélection 2, etc.
  - Les miniatures et les aperçus en taille réelle affichent toutes les sélections avec des couleurs indexées
  - Les sélections de grille ont une marge de 1pt depuis les bords d'écran pour une meilleure visibilité

### Modifié

- L'ordre des fenêtres multiples suit désormais l'ordre de sélection au lieu de l'ordre Z de la barre latérale
  - La première fenêtre sélectionnée est toujours la principale ; les fenêtres ajoutées par Cmd+clic sont ajoutées dans l'ordre
  - La sélection par plage Shift+clic conserve la fenêtre d'ancrage comme principale
  - Affecte l'application des préréglages, la mise au premier plan (Entrée) et l'affichage de l'aperçu

## [3.4.0] - 2026-03-28

### Ajouté

- Sélection multiple de fenêtres dans la barre latérale avec actions groupées
    - Clic sur l'en-tête d'une app pour sélectionner toutes ses fenêtres
    - Cmd+clic pour ajouter/retirer des fenêtres individuellement
    - Shift+clic pour sélectionner une plage continue de fenêtres
- Actions groupées en sélection multiple : mettre au premier plan (en conservant l'ordre Z de la barre latérale), redimensionner/déplacer vers la grille, déplacer vers un autre écran, fermer/quitter
- Lors de la fermeture de plusieurs fenêtres sélectionnées, les apps dont toutes les fenêtres sont sélectionnées sont quittées (sauf le Finder)

### Modifié

- Cliquer sur l'en-tête d'une app dans la barre latérale sélectionne désormais toutes les fenêtres de cette app (auparavant, seule la fenêtre la plus en avant était sélectionnée)
- La sélection d'une fenêtre dans un groupe d'app maintient l'en-tête de l'application en surbrillance
- Pour les apps non-Finder ayant plusieurs fenêtres, un bouton « Quitter l'app » est affiché à côté du bouton « Fermer la fenêtre » dans la barre d'actions
- L'infobulle « Fermer la fenêtre » affiche désormais le nom de la fenêtre (ex. : Fermer « Document »)

## [3.3.2] - 2026-03-28

### Ajouté

- Les raccourcis clavier pour « Fenêtre suivante », « Fenêtre précédente », « Mettre au premier plan » et « Fermer/Quitter » sont désormais configurables dans la section des raccourcis des préférences
- Nouvel élément de menu contextuel « Fermer les autres fenêtres de [App] » lors d'un clic droit sur une fenêtre dans la barre latérale (affiché uniquement lorsque l'app a plusieurs fenêtres)

### Modifié

- La section de configuration des raccourcis a été réorganisée en deux groupes : les raccourcis d'action sur les fenêtres et les raccourcis de déplacement d'écran
- Les raccourcis de déplacement d'écran sont désormais uniquement globaux ; le support des raccourcis locaux et leurs options de configuration ont été supprimés
- Sur macOS 26 (Tahoe), les boutons de la barre d'outils, le bouton Quitter, les boutons de la barre d'actions et le bouton de menu déroulant utilisent désormais l'effet Liquid Glass interactif, conformément aux Human Interface Guidelines
- La couleur de fond de la fenêtre utilise maintenant la couleur système pour une meilleure compatibilité avec les changements d'apparence de macOS
- Les fenêtres déplacées reviennent désormais à leur position d'origine avec une animation lors de la confirmation d'une sélection, de l'application d'une disposition ou de l'annulation avec Échap

## [3.3.1] - 2026-03-28

### Ajouté

- Lors de la sélection d'une fenêtre dans la barre latérale, les fenêtres superposées sont déplacées vers le bas avec une animation fluide pour rendre la fenêtre sélectionnée visible sans changer le focus
- Un cadre de mise en évidence est affiché autour de la fenêtre actuellement sélectionnée dans la barre latérale

### Corrigé

- Correction de l'ordre de parcours Tab/flèches pour correspondre à l'ordre d'affichage de la barre latérale (groupé par espace, écran et application)
- Les fenêtres déplacées sont restaurées à leur position d'origine lors de l'annulation (Esc) ou de la fermeture de Tiley

## [3.3.0] - 2026-03-27

### Corrigé

- Correction préventive de l'utilisation excessive du CPU pouvant survenir dans les environnements multi-écrans
- Correction d'une boucle de redessin de l'icône de la barre d'état pouvant entraîner une utilisation de 100 % du CPU lorsqu'un badge superposé (notification de mise à jour ou indicateur de débogage) était affiché
- Les fenêtres de Tiley flottent désormais toujours au-dessus des fenêtres normales afin de ne pas être masquées lors du changement par Tab

## [3.2.9] - 2026-03-27

### Corrigé

- Correction de l'ordre de parcours Tab/flèches pour correspondre à l'ordre d'affichage de la barre latérale (groupé par espace, écran et application)

## [3.2.8] - 2026-03-26

### Corrigé

- Correction du problème dans la barre latérale où Tab/flèches alternaient entre seulement deux fenêtres au lieu de parcourir toutes les fenêtres

## [3.2.7] - 2026-03-26

### Corrigé

- Correction d'un plantage lors du lancement en tant qu'élément d'ouverture de session (correction incomplète dans la version 3.2.6)

## [3.2.6] - 2026-03-26

### Corrigé

- Correction d'un plantage lors du lancement en tant qu'élément d'ouverture de session

## [3.2.5] - 2026-03-26

### Modifié

- Fusion des sections Raccourcis et Raccourcis globaux en une seule section
- Interface de configuration des raccourcis unifiée pour tous les types

### Corrigé

- Correction d'un problème où la fenêtre principale pouvait rester visible lorsque l'app passait en arrière-plan
- Correction du cadre de surbrillance tronqué par les coins arrondis et l'encoche sur les écrans intégrés (le cadre est désormais dessiné sous la barre de menus)

## [3.2.4] - 2026-03-26

### Ajouté

- Ajout de raccourcis pour déplacer les fenêtres entre les écrans (principal, suivant, précédent, choisir dans le menu, écran spécifique)

## [3.2.3] - 2026-03-25

### Ajouté

- Ajout d'indicateurs fléchés directionnels au bouton et aux éléments de menu « Déplacer vers l'écran », indiquant visuellement la direction de l'écran cible en fonction de la disposition physique des écrans
- Lorsque la fenêtre sélectionnée se trouve sur un autre écran, la grille superposée affiche désormais une flèche directionnelle et une icône de disposition des écrans au centre, guidant l'utilisateur vers l'emplacement de sa fenêtre

### Modifié

- Ajustement de l'apparence lorsqu'une mise à jour est disponible

## [3.2.2] - 2026-03-25

### Ajouté

- La sélection d'une fenêtre dans la barre latérale la place temporairement au premier plan pour faciliter l'identification ; l'ordre original est restauré lors du changement de fenêtre ou de l'annulation
- L'aperçu de redimensionnement affiche désormais une barre de titre avec l'icône de l'application et le titre de la fenêtre, permettant d'identifier plus intuitivement la fenêtre en cours d'agencement

## [3.2.1] - 2026-03-25

### Corrigé

- Correction de la barre latérale n'affichant aucune fenêtre dans les environnements multi-écrans car le filtrage des espaces ne prenait en compte que l'espace actif d'un seul écran

## [3.2.0] - 2026-03-25

### Ajouté

- Lorsque plusieurs espaces Mission Control existent, la barre latérale n'affiche que les fenêtres de l'espace actuel
- La grille superposée affiche désormais un aperçu de fenêtre miniature avec les boutons feux tricolores, l'icône de l'app et le titre de la fenêtre à la position actuelle de la fenêtre cible

### Modifié

- La disparition de la superposition est désormais plus réactive lors de l'application de dispositions ou de la mise au premier plan des fenêtres
- Les fenêtres en mode plein écran natif de macOS quittent désormais automatiquement le plein écran avant le redimensionnement

## [3.1.1] - 2026-03-24

### Corrigé

- Correction de l'affichage en mosaïque au lieu du remplissage pour les miniatures des fonds d'écran système
- Correction de l'affichage incorrect des fonds d'écran dynamiques ; ajout de la prise en charge des miniatures pour les fonds d'écran Sequoia, Sonoma, Ventura, Monterey et Macintosh
- Le texte de la barre de menus dans l'aperçu de la grille s'adapte désormais à la luminosité du fond d'écran (noir sur fond clair, blanc sur fond sombre, comme sous macOS)

## [3.1.0] - 2026-03-24

### Modifié

- Remplacement des menus kebab (…) au survol dans la liste des fenêtres par des menus contextuels natifs macOS (clic droit)
- Ajout de boutons d'action (Déplacer vers l'écran, Fermer/Quitter, Masquer les autres apps) à côté du champ de recherche de la barre latérale
- Les miniatures de grille des préréglages de disposition reflètent désormais le rapport d'aspect de la zone utilisable de l'écran (hors barre de menus et Dock), s'adaptant à l'orientation portrait ou paysage.

### Corrigé

- Correction d'un problème où le redimensionnement de fenêtres échouait parfois lors du déplacement vers un autre écran (en particulier vers un moniteur portrait plus haut), grâce à l'introduction d'un mécanisme de nouvelle tentative pour les déplacements inter-écrans

### Supprimé

- Suppression des boutons de menu kebab et de fermeture au survol des lignes de la barre latérale (remplacés par les menus contextuels et la barre d'actions)

## [3.0.1] - 2026-03-23

### Ajouté

- Lors de la mise au premier plan d'une fenêtre via Entrée ou double-clic, la fenêtre est désormais déplacée vers l'écran où se trouve le pointeur de la souris si celui-ci diffère. La fenêtre est repositionnée pour s'adapter à l'écran et n'est redimensionnée qu'en cas de nécessité.

### Modifié

- Amélioration des performances d'affichage de la superposition d'environ 80 % grâce au pooling/réutilisation des contrôleurs, au chargement différé de la liste des fenêtres et au rendu prioritaire de l'écran cible
- Renommage du paramètre interne de journal de débogage de `useAppleScriptResize` en `enableDebugLog` pour mieux refléter son utilité

### Corrigé

- Correction du redimensionnement de fenêtre échouant silencieusement sur l'écran principal pour certaines applications (ex. Chrome). Le mécanisme de rebond utilisé pour les écrans secondaires est désormais appliqué à l'écran principal
- Correction : cliquer sur l'icône de la barre de menus lorsque la superposition est visible ferme désormais la superposition (comme ESC) au lieu d'ouvrir la fenêtre principale

## [3.0.0] - 2026-03-23

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
