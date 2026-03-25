# Änderungsprotokoll

## [Unreleased]

### Geändert

- Darstellung bei verfügbarem Update angepasst

## [3.2.2] - 2026-03-25

### Hinzugefügt

- Bei Auswahl eines Fensters in der Seitenleiste wird es vorübergehend in den Vordergrund gebracht; beim Wechsel zu einem anderen Fenster oder Abbrechen wird die ursprüngliche Reihenfolge wiederhergestellt
- Die Größenänderungsvorschau zeigt nun eine Titelleiste mit App-Symbol und Fenstertitel an, sodass leichter erkennbar ist, welches Fenster angeordnet wird

## [3.2.1] - 2026-03-25

### Behoben

- Seitenleiste zeigte in Multi-Screen-Umgebungen keine Fenster an, da die Space-Filterung nur den aktiven Space eines einzelnen Displays berücksichtigte

## [3.2.0] - 2026-03-25

### Hinzugefügt

- Bei mehreren Mission Control Spaces zeigt die Seitenleiste nur Fenster des aktuellen Space an
- Das Raster-Overlay zeigt jetzt eine Miniatur-Fenstervorschau mit Ampelschaltflächen, App-Symbol und Fenstertitel an der aktuellen Position des Zielfensters an

### Geändert

- Das Ausblenden des Overlays reagiert nun schneller beim Anwenden von Layouts oder beim In-den-Vordergrund-Bringen von Fenstern
- Fenster im nativen macOS-Vollbildmodus werden vor der Größenänderung automatisch aus dem Vollbildmodus geholt

## [3.1.1] - 2026-03-24

### Behoben

- Systemhintergrund-Miniaturansichten wurden fälschlicherweise gekachelt statt als Füllung dargestellt
- Falsche Darstellung dynamischer Hintergrundbilder behoben; Miniaturansicht-Unterstützung für Sequoia-, Sonoma-, Ventura-, Monterey- und Macintosh-Provider-Hintergründe hinzugefügt
- Menüleistentext in der Rastervorschau passt sich jetzt der Hintergrundbildhelligkeit an (schwarz bei hellen Hintergründen, weiß bei dunklen, wie in macOS)

## [3.1.0] - 2026-03-24

### Geändert

- Hover-Kebab-Menüs (…) in der Fensterliste durch native macOS-Kontextmenüs (Rechtsklick) ersetzt
- Aktionsschaltflächen (Auf Bildschirm verschieben, Schließen/Beenden, Andere Apps ausblenden) neben dem Suchfeld der Seitenleiste hinzugefügt
- Die Raster-Vorschaubilder der Layout-Voreinstellungen spiegeln nun das Seitenverhältnis des nutzbaren Bildschirmbereichs (ohne Menüleiste und Dock) wider und passen sich an Hoch- oder Querformat an.

### Behoben

- Fenstergrößenänderung schlug manchmal fehl, wenn ein Fenster auf einen anderen Bildschirm verschoben wurde (insbesondere auf einen höheren Hochformat-Monitor). Behoben durch einen Wiederholungsmechanismus bei bildschirmübergreifenden Verschiebungen.

### Entfernt

- Hover-Kebab-Menü-Schaltflächen und Hover-Schließen-Schaltflächen aus den Seitenleistenzeilen entfernt (durch Kontextmenüs und Aktionsleiste ersetzt)

## [3.0.1] - 2026-03-23

### Hinzugefügt

- Beim Aktivieren eines Fensters per Enter oder Doppelklick wird das Fenster nun auf den Bildschirm verschoben, auf dem sich der Mauszeiger befindet, falls dieser abweicht. Das Fenster wird bevorzugt repositioniert und nur bei Bedarf in der Größe angepasst.

### Geändert

- Overlay-Anzeigeleistung um ~80 % verbessert durch Controller-Pooling/-Wiederverwendung, verzögertes Laden der Fensterliste und priorisiertes Rendern des Zielbildschirms
- Interne Debug-Log-Einstellung von `useAppleScriptResize` in `enableDebugLog` umbenannt, um den tatsächlichen Zweck besser widerzuspiegeln

### Behoben

- Fenstergrößenänderung auf dem primären Bildschirm bei einigen Apps (z. B. Chrome) wurde stillschweigend ignoriert. Der für sekundäre Bildschirme verwendete Bounce-Retry-Mechanismus wird nun auch auf dem primären Bildschirm angewendet
- Klick auf das Menüleisten-Symbol bei sichtbarem Overlay schließt nun das Overlay (wie ESC), statt das Hauptfenster zu öffnen

## [3.0.0] - 2026-03-23

### Hinzugefügt

- TelemetryDeck Analytics SDK für datenschutzfreundliche Nutzungsstatistiken integriert (Overlay geöffnet, Layout angewendet, Preset angewendet, Einstellungen geändert)
- Fenster in der Seitenleiste werden nach Bildschirm und Anwendung gruppiert; Apps mit mehreren Fenstern zeigen einen App-Header mit eingerückten Fensterzeilen
- Bildschirm-Header in der Seitenleiste haben ein Menü mit „Fenster sammeln" und „Fenster verschieben" zum Verwalten von Fenstern über Bildschirme hinweg
- App-Header-Menü mit „Alle Fenster auf anderen Bildschirm verschieben", „Andere ausblenden" und „Beenden"
- Menü für Einzelfenster-Apps mit „Auf anderen Bildschirm verschieben", „Andere ausblenden" und „Beenden"
- Leere Bildschirme (ohne Fenster) werden in der Seitenleiste mit ihrem Bildschirm-Header angezeigt

### Geändert

- Der Gitterhintergrund spiegelt nun die macOS-Hintergrundbild-Anzeigeeinstellungen korrekt wider (Füllen, Anpassen, Strecken, Zentrieren und Kacheln), einschließlich korrekter Kachelskalierung, physischem Pixelverhältnis für den Zentrierung-Modus und Füllfarbe für Letterbox-Bereiche
- Die Layout-Rastervorschau zeigt nun Menüleiste, Dock und Notch und vermittelt so ein realistischeres Bild der tatsächlichen Anzeige

### Behoben

- Fenster wurde nach Größenänderung an eine unerwartete Position verschoben, wenn die aktuelle Position bereits der Zielposition entsprach. Umgehung der AX-Deduplizierung durch Vor-Verschiebung
- Reduziertes Flackern beim Ändern der Fenstergröße auf Nicht-Primärbildschirmen. Größenänderung wird zuerst vor Ort versucht; nur bei vollständigem Fehlschlag wird auf den Primärbildschirm ausgewichen
- Beim Ausweichen auf den Primärbildschirm wird das Fenster jetzt am unteren Bildschirmrand (fast außerhalb des sichtbaren Bereichs) statt an der oberen linken Ecke platziert, um Flackern zu minimieren

## [2.2.0] - 2026-03-21

### Geändert

- Nicht ausgewählte Rasterkacheln sind jetzt transparent
- Das Seitenverhältnis des Rasters entspricht jetzt dem sichtbaren Bildschirmbereich (ohne Menüleiste und Dock); wird das Raster zu hoch, wird die Breite proportional reduziert, damit mindestens 4 Presets sichtbar bleiben
- Der Hintergrund des Layout-Rasters zeigt jetzt das Desktop-Bild (halbtransparent, abgerundete Ecken)
- Per Drag ausgewählte Zellen sind jetzt halbtransparent, sodass das Desktop-Bild darunter sichtbar ist
- Der Vorschau-Hover-Highlight im Raster verwendet jetzt denselben Stil wie die Drag-Auswahl

### Hinzugefügt

- Die Fensterlisten-Seitenleiste wird jetzt bei Multi-Monitor-Setups auf allen Bildschirmen angezeigt, nicht nur auf dem Zielbildschirm
- Seitenleistenstatus (Sichtbarkeit, ausgewähltes Element, Suchtext) wird zwischen allen Bildschirmfenstern synchronisiert
- Optionales Debug-Log für Größenänderungen (`~/tiley.log`) (Einstellungen > Fehlersuche)

### Behoben

- Fensterplatzierung verwendete veraltete Bildschirmgeometrie, wenn das Dock oder die Menüleiste während der Overlay-Anzeige automatisch ein-/ausgeblendet wurde
- Fenstergrößenänderung schlug auf Nicht-Primärbildschirmen in gemischten DPI-Konfigurationen fehl; das Fenster wird jetzt vorübergehend zum Primärbildschirm verschoben und dann an der Zielposition platziert
- Position wurde nach Größenänderung nicht angewendet, wenn Apps die Positionsänderung stillschweigend rückgängig machen (AX-Deduplizierungs-Workaround)
- Wenn die Mindestfenstergröße einer App die angeforderte Größe verhindert, wird die Fensterposition neu berechnet, damit es im sichtbaren Bildschirmbereich bleibt
- Sichtbares Fensterflackern beim Wechseln des Zielfensters zwischen Bildschirmen behoben; Fenster werden beim Bildschirmwechsel nicht mehr neu erstellt

## [2.1.0] - 2026-03-20

### Hinzugefügt

- Doppelklick auf ein Fenster in der Seitenleiste bringt es in den Vordergrund und schließt das Layout-Raster
- Kontextmenü (Auslassungspunkte-Taste) in den Fensterzeilen der Seitenleiste mit drei Aktionen:
  - „Andere Fenster von [App] schließen" — schließt andere Fenster derselben App (nur angezeigt, wenn die App mehrere Fenster hat)
  - „[App] beenden" — beendet die Anwendung
  - „Fenster außer [App] ausblenden" — blendet alle anderen Anwendungen aus (Cmd-H-Äquivalent), blendet die ausgewählte App wieder ein, falls sie ausgeblendet war
- Ausgeblendete (Cmd-H) Anwendungen erscheinen jetzt als Platzhaltereinträge in der Seitenleiste (nur App-Name) und werden mit 50 % Deckkraft angezeigt
- Beim Auswählen einer ausgeblendeten App (Enter, Doppelklick, Raster-/Layout-Größenänderung) wird sie automatisch eingeblendet und das vorderste Fenster wird verwendet

## [2.0.3] - 2026-03-19

### Hinzugefügt

- Sanfte Sparkle-Update-Erinnerungen: Wenn eine Hintergrundprüfung eine neue Version findet, erscheint ein roter Badge-Punkt am Menüleistensymbol und „Update verfügbar"-Labels neben dem Zahnrad-Button und dem „Nach Updates suchen"-Button in den Einstellungen
- Wenn das Menüleistensymbol ausgeblendet ist, wird es bei Update-Erkennung vorübergehend mit Badge angezeigt und nach Ende der Update-Sitzung wieder ausgeblendet

### Geändert

- Das Einstellungsfenster wird jetzt ausgeblendet, wenn Sparkle ein Update findet (zuvor erst beim Download-Start), und beim Abbrechen wiederhergestellt
- Der Titel des Einstellungsfensters ist jetzt in allen unterstützten Sprachen lokalisiert
- Versionsnummer vom Einstellungstitel in den Update-Bereich neben den „Nach Updates suchen"-Button verschoben

## [2.0.2] - 2026-03-19

### Hinzugefügt

- Schließen-Button in der Fensterlisten-Seitenleiste: Beim Überfahren eines Fensternamens erscheint ein ×-Button zum Schließen des Fensters
- Einstellung „App beenden beim Schließen des letzten Fensters" (Einstellungen > Fenster): Bei Aktivierung (Standard) wird die App beim Schließen des letzten Fensters beendet; bei Deaktivierung wird nur das Fenster geschlossen
- Tooltip des Schließen-Buttons zeigt den Fensternamen; wenn die App beendet wird, wird der App-Name angezeigt
- „/" Tastenkürzel zum Schließen des ausgewählten Fensters (oder Beenden der App, wenn es das letzte Fenster ist und die Einstellung aktiviert ist)

## [2.0.1] - 2026-03-19

### Geändert

- Einstellungspanel im Tahoe-Stil neu gestaltet: Abschnitte mit Glas-Hintergrund (Liquid Glass ab macOS 26+), kompakte Symbolleiste mit Zurück-/Beenden-Buttons und iOS-ähnliche gruppierte Zeilen mit Inline-Steuerelementen

## [2.0.0] - 2026-03-19

### Geändert

- Das Dropdown-Menü zur Fensterzielauswahl wurde durch ein Seitenleisten-Panel mit Liquid Glass (macOS Tahoe) ersetzt; enthält ein Suchfeld mit vollständiger IME-Unterstützung, Navigation per Pfeiltasten und Tab/Umschalt+Tab sowie Cmd+F zum Ein-/Ausblenden

### Verbessert

- Fenster in der Seitenleiste werden in Z-Reihenfolge (vorne nach hinten) aufgelistet statt nach Anwendung gruppiert
- Nicht-Standard-Fenster (Paletten, Symbolleisten usw.) werden aus der Fensterziel-Liste gefiltert, sodass nur größenveränderbare Dokumentfenster angezeigt werden

## [1.2.7] - 2026-03-18

### Verbessert

- Das Hauptfenster wird jetzt automatisch geschlossen, wenn Sparkle mit dem Herunterladen eines Updates beginnt

### Behoben

- Sichtbare Nahtstellen in der Vorschau der Größenänderungsbeschränkungen behoben, wenn gleichzeitig horizontale und vertikale Überlauf- (rot) oder Unterlaufbereiche (gelb) angezeigt werden

## [1.2.6] - 2026-03-18

### Behoben

- Beim Ändern der Größe eines Hintergrundfensters derselben Anwendung über Tab-Wechsel wird das Fenster jetzt in den Vordergrund gebracht, wenn es hinter anderen Fenstern dieser Anwendung verdeckt wäre

## [1.2.5] - 2026-03-18

### Hinzugefügt

- Erkennung von Fenstergrößenbeschränkungen: Automatische Erkennung der achsenweisen Größenänderbarkeit durch eine schnelle 3-stufige Prüfung (nicht änderbar → Vollbildtaste → 1px-Probe als Rückfall)
- Layout-Vorschau-Overlay zeigt jetzt rote Bereiche, in denen das Fenster nicht vergrößert werden kann, und gelbe Bereiche, in denen es nicht verkleinert werden kann – visuelle Rückmeldung zu Größenbeschränkungen vor der Anwendung

## [1.2.4] - 2026-03-17

### Verbessert

- Layout-Vorlagen-Bearbeitungs-UI verfeinert: Löschen-Schaltfläche neben die Bestätigungsschaltfläche verschoben, Bearbeitungs-/Aktionsschaltflächen in einer eigenen Spalte platziert, um Überlappungen mit Tastenkombinationen zu vermeiden
- Rasterauswahl im Bearbeitungsmodus jetzt änderbar: Durch Ziehen im Raster kann die Position der Vorlage mit Live-Vorschau und Hervorhebung aktualisiert werden

## [1.2.3] - 2026-03-17

### Verbessert

- Feinabstimmung der Benutzeroberfläche zur Bearbeitung von Layout-Vorlagen: Löschen-Schaltfläche wird als Overlay über der Rastervorschau angezeigt, mit Bestätigungsdialog, opakem Hover-Hintergrund und einheitlichem Schaltflächenstil

## [1.2.2] - 2026-03-17

### Geändert

- Bearbeitung von Layout-Vorlagen für ein intuitiveres Einstellungserlebnis neu gestaltet

## [1.2.1] - 2026-03-17

### Behoben

- Dialog „In Programme bewegen" wurde fälschlich anstelle von „In Programme kopieren" angezeigt, wenn die App aus einem heruntergeladenen DMG gestartet wurde (Gatekeeper App Translocation verhinderte die Erkennung des Disk-Image-Pfads)

## [1.2.0] - 2026-03-17

### Hinzugefügt

- Fensterziel-Umschaltung: Tab / Umschalt+Tab drücken, während das Overlay angezeigt wird, um zwischen verfügbaren Fenstern zu wechseln
- Fensterziel-Dropdown: Klicken Sie auf den Zielinfobereich, um ein Fenster aus einem Popup-Menü auszuwählen
- Tab und Umschalt+Tab sind jetzt reserviert und können nicht als Layout-Tastenkürzel zugewiesen werden

## [1.1.8] - 2026-03-16

### Hinzugefügt

- Nach dem Kopieren von einem DMG wird angeboten, das Disk-Image auszuwerfen und die DMG-Datei in den Papierkorb zu verschieben
- Erkennung eines eingehängten Tiley-DMG beim Start aus /Programme (z. B. nach manuellem Kopieren im Finder) mit Angebot zum Auswerfen und Löschen

## [1.1.7] - 2026-03-16

### Geändert

- Verteilungsformat von zip auf DMG mit Programme-Verknüpfung und benutzerdefiniertem Finder-Layout (große Symbole, quadratisches Fenster) umgestellt

### Behoben

- „In Programme bewegen" schlug mit einem Nur-Lese-Volume-Fehler fehl, wenn die App aus einer heruntergeladenen zip ohne vorheriges Verschieben gestartet wurde (Gatekeeper App Translocation)
- „In Programme kopieren"-Dialog wird jetzt anstelle von „Bewegen" angezeigt, wenn die App von einem Disk-Image (DMG) gestartet wird

## [1.1.6] - 2026-03-16

### Behoben

- Einstellungsfenster erforderte auf Multi-Screen-Setups zwei Aktivierungen zum Öffnen (Menüleistensymbol, Cmd+, und Tiley-Menü → Einstellungen waren betroffen)

## [1.1.5] - 2026-03-16

### Hinzugefügt

- Multi-Screen-Overlay: Das Layout-Gitterfenster erscheint jetzt gleichzeitig auf allen angeschlossenen Bildschirmen
- Bildschirmübergreifendes Tiling: Ziehen Sie das Gitter oder klicken Sie auf einen Preset auf einem sekundären Bildschirm, um das Zielfenster dorthin zu verschieben
- Vorschau-Overlay erscheint auf dem Bildschirm, auf dem das Preset-Fenster angezeigt wird

### Behoben

- Maximieren-Layout füllte nicht den gesamten Bildschirm beim Tiling über Displays unterschiedlicher Größe
- Lokale Tastenkürzel (Pfeiltasten, Preset-Hotkeys) funktionierten nach der zweiten Overlay-Aktivierung nicht
- Beim Klicken auf ein Hintergrund-App-Fenster wurden nur einige Overlay-Fenster geschlossen; jetzt werden alle gleichzeitig geschlossen
- Preset-Hover/Auswahl-Hervorhebung wurde auf allen Bildschirmen angezeigt; jetzt nur auf dem Bildschirm mit dem Mauszeiger

## [1.1.4] - 2026-03-15

### Behoben

- „Dock-Symbol anzeigen"-Schalter funktionierte nicht: Dock-Symbol erschien nicht beim Aktivieren, und Deaktivieren ließ das Fenster verschwinden
- App wurde unerwartet beendet, wenn alle Fenster geschlossen wurden
- Fensterziel war Tiley selbst, wenn die App per Doppelklick gestartet wurde; jetzt wird korrekt das Fenster der zuvor aktiven App verwendet
- Hauptfenster erschien beim Start als Anmeldeobjekt: Das Fenster öffnet sich nicht mehr bei automatischem Start beim Systemstart

## [1.1.3] - 2026-03-15

### Behoben

- Gitter-Vorschau-Overlay blieb manchmal auf dem Bildschirm sichtbar, was zu gestapelten Duplikat-Overlays führte

## [1.1.2] - 2026-03-15

### Hinzugefügt

- Lokalisierung: Spanisch, Deutsch, Französisch, Portugiesisch (Brasilien), Russisch, Italienisch

## [1.1.1] - 2026-03-15

## [1.1.0] - 2026-03-15

### Hinzugefügt

- Dunkelmodus-Unterstützung: Alle UI-Elemente passen sich automatisch an die Systemdarstellung an

### Geändert

- Tastenkürzel-Anzeige verwendet jetzt Symbole (⌃ ⌥ ⇧ ⌘ ← → ↑ ↓) anstelle englischer Tastennamen

### Behoben

- Hauptfenster wird jetzt automatisch ausgeblendet, wenn Sparkle den Update-Dialog anzeigt

## [1.0.1] - 2026-03-15

### Behoben

- Fehlende Lokalisierung für Tastenkürzel-Hinzufügen-Button-Tooltips („Tastenkürzel hinzufügen" / „Globales Tastenkürzel hinzufügen")

## [1.0.0] - 2026-03-14

### Hinzugefügt

- Aufforderung zum Verschieben der App nach /Programme, wenn sie von einem anderen Ort gestartet wird
- Globales Flag pro Tastenkürzel: Jedes Tastenkürzel innerhalb eines Layout-Presets kann jetzt einzeln als global oder lokal festgelegt werden
- Separate Hinzufügen-Buttons für reguläre und globale Tastenkürzel mit sofortigen Popover-Tooltips

### Geändert

- Globale Tastenkürzel-Einstellung von Preset-Ebene auf Tastenkürzel-Ebene verschoben
- Bestehende Presets mit dem alten Preset-Level-Global-Flag werden automatisch migriert

## [0.9.0] - 2026-03-14

- Erstveröffentlichung

### Hinzugefügt

- Gitter-Overlay für Fenster-Tiling mit anpassbarer Gittergröße
- Globales Tastenkürzel (Umschalt + Befehl + Leertaste) zum Aktivieren des Overlays
- Über Gitterzellen ziehen, um den Zielfensterbereich zu definieren
- Layout-Presets zum Speichern und Wiederherstellen von Fensteranordnungen
- Multi-Display-Unterstützung
- Beim Anmelden starten
- Lokalisierung: Englisch, Japanisch, Koreanisch, Vereinfachtes Chinesisch, Traditionelles Chinesisch
