# Änderungsprotokoll

## [Unreleased]

### Geändert

- Seitenleistensuche verwendet jetzt Teilsequenz-Matching — die Eingabe von „f1" findet „Finder Users1" auch bei nicht aufeinanderfolgenden Zeichen
- Seitenleistensuche berücksichtigt auch den ursprünglichen (nicht lokalisierten) App-Namen, sodass „ai" auch „Mail" findet, wenn die App lokalisiert angezeigt wird

### Behoben

- Beim Schließen eines Fensters wurden nachfolgende Fenster in der Seitenleiste manchmal unbeabsichtigt mehrfach ausgewählt
- Das Miniaturfenster im Raster wurde nach dem Schließen eines Fensters nicht auf das neue Ziel aktualisiert

## [4.2.3] - 2026-04-05

### Hinzugefügt

- Das Kontextmenü enthält nun „N Fenster schließen", wenn mehrere Fenster ausgewählt sind; Apps mit nur einem Fenster werden beendet statt nur das Fenster zu schließen, und die Auswahl wird danach auf ein einzelnes Fenster zurückgesetzt

### Geändert

- Beim Überfahren einer Rasterzelle wird nun eine Miniatur-Fenstervorschau mit App-Symbol und Titelleiste angezeigt, anstatt eines einfachen blauen Rechtecks – passend zur Darstellung während des Ziehens
- Nach dem Schließen eines Fensters über das Kontextmenü oder die „/"-Taste wird in der Seitenleiste nun das Element unterhalb des geschlossenen Fensters ausgewählt; wenn kein Element darunter vorhanden ist, wird das darüber liegende ausgewählt

### Behoben

- Verschobene (Nicht-Ziel-)Fenster kehren nach Anwendung eines Multi-Fenster-Layouts nun korrekt an ihre ursprüngliche Position zurück
- „Letzte Auswahl" wird nun korrekt angezeigt, auch wenn das primäre Layout mit einem Preset übereinstimmt, das sekundäre Layouts enthält (z. B. wird die manuelle Auswahl der oberen Hälfte nicht mehr durch das Preset „Obere Hälfte" ausgeblendet, das auch ein sekundäres Layout für die untere Hälfte enthält)
- Rastervorschau-Overlay wurde beim Überfahren des Rasterbereichs in den Einstellungen nicht angezeigt
- Rastervorschau-Overlay wurde beim Ändern von Zeilen, Spalten oder Abstandswerten in den Einstellungen nicht in Echtzeit aktualisiert
- „Schreibtisch anzeigen" und Mission Control werden beim Aufrufen von Tiley über das globale Tastenkürzel oder das Menüleistensymbol automatisch beendet
- Tiley-Overlay-Fenster wird nicht mehr in Mission Control / Exposé angezeigt

## [4.2.2] - 2026-04-04

### Geändert

- Overlay-Fenster werden jetzt mit Transparenz Null vorgerendert und auf dem Bildschirm gehalten, sodass zum Anzeigen des Layout-Rasters nur eine Änderung des Alphawerts erforderlich ist — die wahrgenommene Latenz wird deutlich reduziert
- Das Einstellungsfenster wird jetzt automatisch geschlossen, wenn eine andere Anwendung angeklickt wird; Tiley bleibt ausgeblendet, bis das globale Tastenkürzel erneut gedrückt wird

### Behoben

- Klick auf das Dock-Symbol bei geöffnetem Einstellungsfenster zeigte „Keine Fenster" anstelle der Einstellungen
- Das Einstellungsfenster verschwand dauerhaft beim Deaktivieren von „Dock-Symbol anzeigen"
- Das globale Tastenkürzel funktionierte nicht mehr, nachdem das Einstellungsfenster den Fokus an eine andere Anwendung verloren hatte

## [4.2.1] - 2026-04-04

### Geändert

- Chevron-Anzeige zur Größenänderungs-Schaltfläche hinzugefügt, um deutlicher zu machen, dass es sich um ein Dropdown-Menü handelt
- Timing der Größenänderung verbessert, sodass das Tiley-Fenster verschwindet, bevor das Zielfenster angepasst wird, was die Bedienung intuitiver macht

## [4.2.0] - 2026-04-04

### Hinzugefügt

- Fenster über die Symbolleiste oder das Kontextmenü auf vordefinierte Größen (16:9, 16:10, 4:3, 9:16) ändern; Größen, die den aktuellen Bildschirm überschreiten, werden automatisch ausgeschlossen
- Live-Vorschau beim Überfahren von Größenänderungs-Menüeinträgen: Echtgröße-Overlay auf dem Zielbildschirm und Miniatur-Fenstervorschau im Raster (gleicher Stil wie die Voreinstellungs-Layout-Vorschau)
- Miniatur-Fenstervorschau (mit Titelleiste und App-Symbol) wird jetzt während der Raster-Auswahl per Ziehen angezeigt

## [4.1.2] - 2026-04-03

### Hinzugefügt

- Auswahlreihenfolge-Indexabzeichen werden rechts neben Seitenleisten-Fensterelementen angezeigt, wenn zwei oder mehr Fenster ausgewählt sind

### Geändert

- Die Fensterliste in der Seitenleiste wird nun über Workspace-Ereignis-Listener (App-Aktivierung, -Start, -Beendigung) im Hintergrund vorab zwischengespeichert, sodass sie beim Öffnen des Overlays sofort angezeigt wird
- Hervorhebungsverhalten für nach App gruppierte Seitenleistenelemente verbessert. Der App-Header wird nur noch als ausgewählt angezeigt, wenn alle zugehörigen Fenster ausgewählt sind, und beim Überfahren des App-Headers werden sowohl der Header als auch alle untergeordneten Fenster hervorgehoben
- Verbessertes Verhalten beim Beenden des Vollbildmodus: AXFullScreen-Attribut wird jetzt direkt gesetzt (mit Tastendruck als Fallback), Wartezeit bis zu 2 Sekunden für den Abschluss der Animation

### Behoben

- Problem behoben, dass sich das Overlay nicht öffnete, wenn die vorderste Anwendung keine Fenster hat. Es wird nun eine „Keine Fenster"-Meldung angezeigt und das Ziehen deaktiviert
- Problem behoben, dass Finders Desktop als größenveränderbares Fenster behandelt wurde. Bei fokussiertem Desktop wird nun das vorderste echte Finder-Fenster ausgewählt, oder „Keine Fenster" angezeigt, wenn keines vorhanden ist
- Overlay öffnete sich nicht, wenn die vorderste Anwendung keine Fenster hat (z. B. Finder ohne offene Fenster, reine Menüleisten-Apps); es wird nun auf das oberste sichtbare Fenster auf dem Bildschirm zurückgegriffen
- Fensterposition wurde bei einigen Apps (z. B. Notion) auf nicht-primären Bildschirmen nicht korrekt angewendet. Positionsüberprüfung mit Wiederholungslogik nach der Größenänderung hinzugefügt, um Apps zu behandeln, die die Position asynchron zurücksetzen

## [4.1.1] - 2026-03-31

### Geändert

- Standard-Tastenkürzel für die Auswahl des nächsten Fensters von Tab auf Space geändert; vorheriges Fenster von Shift+Tab auf Shift+Space geändert
- Verschobene Fenster kehren beim Schließen des Overlays nun immer animiert an ihre ursprüngliche Position zurück

## [4.1.0] - 2026-03-31

### Hinzugefügt

- Fensterwechsel bei gehaltenen Modifikatortasten (Cmd+Tab-ähnlich): Nach dem Öffnen des Overlays die Toggle-Modifikatortasten gedrückt halten und die Auslösetaste wiederholt drücken, um zwischen Fenstern zu wechseln; beim Loslassen der Modifikatortasten wird das ausgewählte Fenster in den Vordergrund gebracht; Layout-Lokalkürzel bei gehaltenen Modifikatortasten anwenden
- Abschnitt für Drittanbieter-Lizenzhinweise in den Einstellungen (Sparkle, TelemetryDeck)

### Geändert

- Einstellungs- und Berechtigungsfenster sind jetzt separate Fenster auf normaler (nicht schwebender) Ebene, sodass Sparkle-Update-Dialoge und andere Systemfenster darüber angezeigt werden können
- Die Seitenleiste ist jetzt immer sichtbar; die Ein-/Ausblenden-Schaltfläche wurde entfernt
- Einstellungs-Schaltfläche von der Fußleiste an den linken Rand der Seitenleisten-Aktionsleiste verschoben
- Die Minibildschirm-Vorschau hat jetzt unabhängig vom Displaytyp an allen vier Ecken abgerundete Ecken
- Die Titelleiste des Miniaturfensters zeigt jetzt den Anwendungsnamen zusammen mit dem Fenstertitel an
- Das „Update verfügbar"-Abzeichen wurde durch einen roten Punkt auf der Einstellungs-Schaltfläche und einen Tooltip ersetzt; im Einstellungsfenster wird ein Popover auf der „Nach Updates suchen"-Schaltfläche angezeigt

## [4.0.9] - 2026-03-30

### Behoben

- Fenstergrößenänderung schlug bei bestimmten Apps fehl und die Position wurde verschoben: Die Fallback-Bounce-Position bei abgelehnter Größenänderung lag am unteren Bildschirmrand (kein Platz zum Vergrößern), wodurch das Fenster an einer falschen Position hängen blieb. Bounce erfolgt jetzt zum oberen Rand des sichtbaren Bereichs, und bei erneutem Fehlschlag wird die Position explizit wiederhergestellt
- Verschobene Fenster wurden nach Auswahl eines Hintergrundfensters manchmal nicht an ihre ursprüngliche Position zurückgesetzt: Die Wiederherstellung suchte in einer möglicherweise veralteten Fensterliste, was zum Fehlschlag führen konnte. Fensterreferenzen werden jetzt direkt in den Verschiebungs-Tracking-Daten gespeichert, und die Bereinigung wird bis zum Abschluss der Wiederherstellungsanimation verzögert
- Die Schaltflächen „Tastenkürzel hinzufügen" / „Globales Kürzel hinzufügen" reagierten nur bei Klicks nahe der Mitte: Innenabstand und Hintergrund wurden in das Button-Label verschoben, sodass der gesamte sichtbare Bereich klickbar ist

## [4.0.8] - 2026-03-30

### Behoben

- Das Berechtigungsfenster wird beim Anfordern von Bedienungshilfenzugriff nicht mehr über anderen Apps und Systemdialogen angezeigt
- Hintergrundvorschau wurde unter macOS Tahoe 26.4 nicht angezeigt: Anpassung an die Strukturänderung der Hintergrund-Store-plist (`Desktop` → `Linked`-Schlüssel), Fotos-Hintergründe werden aus dem BMP-Cache des Hintergrund-Agenten geladen, `FillScreen`-Platzierungswert (Tahoes Ersatz für `Stretch`) hinzugefügt, Anzeigemodus-Einstellungen für Nicht-System-Hintergrundanbieter aktiviert
- Zentrierte und gekachelte Hintergrund-Anzeigemodi stellten Bilder zu klein dar, wenn die DPI-Metadaten des Bildes nicht 72 waren (z. B. Retina-Screenshots mit 144 DPI); es werden nun immer die tatsächlichen Pixelmaße verwendet

## [4.0.7] - 2026-03-29

### Behoben

- Der gekachelte Hintergrund-Anzeigemodus wurde in der Mini-Bildschirmvorschau nicht korrekt dargestellt (der Platzierungswert „Tiled" aus der macOS-Hintergrund-Store-plist wurde nicht korrekt zugeordnet)
- Debug-Protokollierung für die Hintergrund-Auflösungspipeline hinzugefügt, um Hintergrund-Anzeigeprobleme zu diagnostizieren

## [4.0.6] - 2026-03-29

### Hinzugefügt

- Beim Überfahren eines Multi-Layout-Presets werden Layout-Indexnummern im Mini-Bildschirm-Raster, in der Originalgrößen-Vorschau und in der Seitenleisten-Fensterliste angezeigt, sodass unabhängig vom Farbsehvermögen sofort erkennbar ist, welches Layout auf welches Fenster angewendet wird

### Geändert

- Einstellungsfenster-UI an das macOS Tahoe Look & Feel angepasst: Toolbar- und Action-Bar-Schaltflächen vereinheitlicht auf Kapselform mit systemadaptiven Hover-/Press-Hintergründen, Einstellungsbereich-Karten ohne Rahmen mit hellem Grau-Hintergrund, Umschalter auf System-Einstellungen-Größe verkleinert, Tastenkürzel-Liste neu strukturiert mit eigenem Bereich „Tastenkürzel zum Verschieben auf Display"

### Behoben

- Seitenleisten-Fenster, die die Preset-Layout-Anzahl überschreiten, werden jetzt korrekt in der Farbe des letzten Layouts statt in der primären Auswahlfarbe angezeigt

## [4.0.5] - 2026-03-29

### Behoben

- Fenster, die zur Anzeige des ausgewählten Zielfensters verschoben wurden, werden jetzt auch bei schnellem Wechsel korrekt an ihre ursprüngliche Position zurückgebracht
- Die Vorschau bei Größenänderung eines einzelnen Fensters war im Vergleich zur Mehrfenster-Layoutvorschau zu blass; verwendet jetzt die gleiche Deckkraft

## [4.0.4] - 2026-03-29

### Hinzugefügt

- Beim Hovern über ein Preset zeigt die Mini-Bildschirm-Layoutvorschau Fenster-Titelleisten (App-Symbol, App-Name, Fenstertitel) an

### Geändert

- Die Titelleiste der Layoutvorschau in Originalgröße zeigt nun den App-Namen zusammen mit dem Fenstertitel an (Format: „App-Name — Fenstertitel")

## [4.0.3] - 2026-03-29

### Hinzugefügt

- Multi-Layout-Presets passen nun auch bei nur einem ausgewählten Fenster mehrere Fenster nach tatsächlicher Z-Reihenfolge (vorderstes zuerst) an
- Wenn weniger Fenster ausgewählt sind als Layout-Definitionen vorhanden, wird das ausgewählte Fenster immer als primär behandelt und die restlichen Plätze werden nach Z-Reihenfolge aufgefüllt
- Beim Hovern über ein Multi-Layout-Preset werden die betroffenen Fensterzeilen in der Seitenleiste mit Layout-Farben (Blau, Grün, Orange, Lila) hervorgehoben

## [4.0.2] - 2026-03-29

### Geändert

- Echtgröße-Layoutvorschau zeigt jetzt nur Vorschauen für die Anzahl der in der Vorlage definierten Auswahlen an (zusätzlich ausgewählte Fenster über die Auswahlanzahl der Vorlage hinaus werden nicht mehr angezeigt)

## [4.0.1] - 2026-03-29

### Geändert

- Auswahlfarbpalette auf 4 Farben (Blau, Grün, Orange, Lila) geändert, sodass die 5. Auswahl dieselbe Farbe wie die 1. hat
- Standardvorlagen (Linke/Rechte/Obere/Untere Hälfte) enthalten jetzt die gegenüberliegende Hälfte als sekundäre Auswahl

## [4.0.0] - 2026-03-29

### Hinzugefügt

- Mehrfachauswahl-Layout-Vorlagen: Definieren Sie mehrere Rasterbereiche pro Vorlage, um verschiedene Fenster an verschiedenen Positionen anzuordnen
  - Jedes Ziehen im Vorlagen-Editor fügt eine neue Auswahl hinzu (1., 2., 3., ...)
  - Jede Auswahl zeigt ihre Indexnummer und einen Löschbutton
  - Überlappende Auswahlen werden verhindert (mit visuellem Feedback)
  - Bei Anwendung einer Mehrfachauswahl-Vorlage werden Fenster nach Auswahlreihenfolge zugewiesen: zuerst ausgewähltes Fenster erhält Auswahl 1, nächstes Auswahl 2 usw.
  - Vorlagen-Miniaturansichten und Echtgrößen-Vorschauen zeigen alle Auswahlen mit indizierten Farben
  - Rasterauswahlen haben einen 1pt-Rand vom Bildschirmrand für bessere Sichtbarkeit

### Geändert

- Mehrfenster-Reihenfolge folgt jetzt der Auswahlreihenfolge statt der Seitenleisten-Z-Reihenfolge
  - Das zuerst ausgewählte Fenster ist immer primär; per Cmd+Klick hinzugefügte Fenster werden in Reihenfolge angehängt
  - Shift+Klick-Bereichsauswahl behält das Ankerfenster als primär
  - Betrifft Layout-Vorlagen-Anwendung, In den Vordergrund bringen (Enter) und Vorschauanzeige

## [3.4.0] - 2026-03-28

### Hinzugefügt

- Mehrfachauswahl von Fenstern in der Seitenleiste mit Stapelaktionen
    - Klick auf App-Header wählt alle Fenster der App aus
    - Cmd+Klick zum Hinzufügen/Entfernen einzelner Fenster
    - Shift+Klick für zusammenhängende Bereichsauswahl
- Stapelaktionen bei Mehrfachauswahl: In den Vordergrund bringen (Seitenleisten-Z-Reihenfolge beibehalten), Größe ändern/zum Raster verschieben, Display wechseln, Schließen/Beenden
- Beim Schließen mehrerer ausgewählter Fenster wird die App beendet, wenn alle ihre Fenster ausgewählt sind (außer Finder)

### Geändert

- Klick auf App-Header in der Seitenleiste wählt nun alle Fenster der App aus (zuvor nur das vorderste Fenster)
- Beim Auswählen eines Fensters innerhalb einer App-Gruppe bleibt der App-Header hervorgehoben
- Für Nicht-Finder-Apps mit mehreren Fenstern wird in der Aktionsleiste neben „Fenster schließen" nun auch eine „App beenden"-Schaltfläche angezeigt
- Der Tooltip „Fenster schließen" zeigt nun den Fensternamen an (z. B. „Dokument" schließen)

## [3.3.2] - 2026-03-28

### Hinzugefügt

- Die Tastenkürzel für „Nächstes Fenster auswählen", „Vorheriges Fenster auswählen", „In den Vordergrund" und „Schließen/Beenden" können jetzt in den Einstellungen konfiguriert werden
- Neuer Kontextmenüeintrag „Andere Fenster von [App] schließen" beim Rechtsklick auf ein Fenster in der Seitenleiste (nur sichtbar, wenn die App mehrere Fenster hat)

### Geändert

- Der Bereich für Tastenkürzel wurde in zwei Gruppen unterteilt: Fensterbefehle und Anzeige-Bewegungen
- Anzeige-Bewegungskürzel sind jetzt nur noch global; lokale Tastenkürzel und deren Einstellungen wurden entfernt
- Auf macOS 26 (Tahoe) verwenden Symbolleisten-Schaltflächen, Beenden-Schaltfläche, Aktionsleisten-Schaltflächen und Dropdown-Menü-Schaltflächen den interaktiven Liquid Glass-Effekt gemäß den Human Interface Guidelines
- Fensterhintergrundfarbe wurde auf die System-Fensterhintergrundfarbe umgestellt, um die Kompatibilität mit macOS-Erscheinungsänderungen zu verbessern
- Verschobene Fenster kehren nun beim Bestätigen einer Auswahl, Anwenden eines Layouts oder Abbrechen mit Escape animiert an ihre ursprüngliche Position zurück

## [3.3.1] - 2026-03-28

### Hinzugefügt

- Bei Auswahl eines Fensters in der Seitenleiste werden überlappende Fenster mit einer sanften Animation nach unten verschoben, um das ausgewählte Fenster ohne Fokuswechsel sichtbar zu machen
- Ein Hervorhebungsrahmen wird um das aktuell in der Seitenleiste ausgewählte Fenster angezeigt

### Behoben

- Tab-/Pfeiltasten-Reihenfolge entspricht nun der Anzeigereihenfolge der Seitenleiste (gruppiert nach Space, Bildschirm und Anwendung)
- Verschobene Fenster werden beim Abbrechen (Esc) oder Schließen von Tiley an ihre ursprüngliche Position zurückgesetzt

## [3.3.0] - 2026-03-27

### Behoben

- Präventive Behebung einer übermäßigen CPU-Auslastung, die in Multi-Display-Umgebungen auftreten konnte
- Behebung einer Neuzeichnungsschleife des Statusleistensymbols, die bei angezeigtem Badge-Overlay (Update-Benachrichtigung oder Debug-Anzeige) zu 100 % CPU-Auslastung führen konnte
- Tiley-Fenster werden nun immer schwebend angezeigt, damit sie beim Tab-Wechsel nicht hinter Zielfenstern verschwinden

## [3.2.9] - 2026-03-27

### Behoben

- Tab-/Pfeiltasten-Reihenfolge entspricht nun der Anzeigereihenfolge der Seitenleiste (gruppiert nach Space, Bildschirm und Anwendung)

## [3.2.8] - 2026-03-26

### Behoben

- Tab-/Pfeiltasten-Navigation in der Seitenleiste wechselte nur zwischen zwei Fenstern statt alle Fenster zu durchlaufen

## [3.2.7] - 2026-03-26

### Behoben

- Absturz beim Starten als Anmeldeobjekt behoben (unvollständige Behebung in 3.2.6)

## [3.2.6] - 2026-03-26

### Behoben

- Absturz beim Starten als Anmeldeobjekt behoben

## [3.2.5] - 2026-03-26

### Geändert

- Kurzbefehle- und Globale-Kurzbefehle-Bereiche zu einem einzigen Bereich zusammengeführt
- Einheitliche Einstellungsoberfläche für alle Kurzbefehltypen

### Behoben

- Ein Problem wurde behoben, bei dem das Hauptfenster sichtbar bleiben konnte, wenn die App in den Hintergrund wechselte
- Hervorhebungsrahmen auf integrierten Displays wurde durch abgerundete Ecken und Notch abgeschnitten – der Rahmen wird nun unterhalb der Menüleiste gezeichnet

## [3.2.4] - 2026-03-26

### Hinzugefügt

- Kurzbefehle zum Verschieben von Fenstern zwischen Bildschirmen hinzugefügt (Hauptbildschirm, nächster, vorheriger, aus Menü wählen, bestimmter Bildschirm)

## [3.2.3] - 2026-03-25

### Hinzugefügt

- Richtungspfeile zu den Schaltflächen und Menüeinträgen „Auf Display verschieben" hinzugefügt, die basierend auf der physischen Bildschirmanordnung die Richtung des Zieldisplays anzeigen
- Wenn sich das ausgewählte Fenster auf einem anderen Display befindet, zeigt das Raster-Overlay nun einen Richtungspfeil und ein Bildschirmanordnungssymbol in der Mitte an, um den Benutzer zum Standort des Fensters zu leiten

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
