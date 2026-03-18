# Änderungsprotokoll

## [Unreleased]

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
