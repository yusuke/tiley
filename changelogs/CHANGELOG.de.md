# Änderungsprotokoll

## [Unreleased]

### Behoben

- Beim Bearbeiten eines Layout-Presets mit bereits zugewiesenen App-Slots war die im gezogenen Rechteck angezeigte Nummer (und dessen Farbe) um eins zu hoch: Die App-Slots wurden mitgezählt, obwohl sie ein Symbol statt einer Nummer anzeigen. Zieh- und Hover-Vorschau verwenden jetzt dieselbe Nummerierung wie die bestätigten Rechtecke.
- Tiley führte bei jedem Fokus- oder Fensterwechsel in einer beliebigen App einen vollständigen Accessibility-Durchlauf über alle geöffneten Fenster durch (plus eine WindowServer-Fensterlisten-Abfrage) — selbst wenn die Fenstergruppierungs-Funktion überhaupt nicht genutzt wurde. Die Aktualisierung der Badge-Overlays kehrt jetzt sofort zurück, wenn weder verknüpfte Gruppen noch ausstehende Gruppenkandidaten existieren, und Fokuswechsel-Ereignisse werden zusammengefasst, sodass ein einzelner Fensterwechsel (der sowohl die Focused-Window- als auch die Main-Window-Accessibility-Benachrichtigung auslöst) höchstens eine statt zwei Aktualisierungen anstößt. Damit entfällt die konstante CPU-/IPC-Hintergrundlast beim normalen App-Wechsel.
- Tileys Overlay las Wallpaper-Metadaten und die Dock-Konfiguration bei jedem SwiftUI-Renderdurchlauf erneut von der Festplatte: Die Wallpaper-Store-Plist wurde bis zu viermal pro Durchlauf neu geparst (und die Wallpaper-Datei zum Auslesen der Pixelmaße erneut geöffnet), und bei sichtbarer Dock-Kante wurden die Dock-Plist sowie alle Dock-App-Icons jedes Mal neu geladen — synchrone Festplatten-I/O auf dem Main-Thread in Mausbewegungs-Frequenz. Die Wallpaper-Anzeigedaten werden jetzt pro Bildschirm zwischengespeichert und bei Änderungen am Wallpaper oder an der Bildschirmkonfiguration verworfen; der Dock-Inhalt wird nur noch einmal pro Fensteröffnung gelesen.
- Beim Ziehen einer Auswahl über das Raster wurde das Bildschirm-Vorschau-Overlay bei jedem Mausereignis neu aufgebaut: Jede Bewegung erzeugte die gesamte SwiftUI-Hosting-View des Overlays neu, selbst wenn sich die hervorgehobenen Zellen nicht geändert hatten. Die Vorschau aktualisiert sich jetzt nur noch, wenn die Auswahl tatsächlich in eine andere Zelle wechselt, und das Overlay verwendet eine einzige Hosting-View wieder, statt sie neu zu erstellen — die CPU-Spitze beim Ziehen entfällt (dieselbe Wiederverwendung gilt auch für Preset-Hover-, Größenänderungs- und Einstellungs-Raster-Vorschauen).
- Beim Verschieben oder Vergrößern einer verknüpften Fenstergruppe pollte Tiley mit 120 Hz über synchrone Accessibility-Aufrufe, führte beim Größenändern pro Tick bis zu drei Prüf-und-Korrektur-Roundtrips je Folgefenster aus und suchte Fenster hunderte Male pro Sekunde per linearem Scan. Das Polling läuft jetzt mit 60 Hz und einem einzigen Prüfdurchlauf pro Tick (die endgültigen Positionen stellt die Korrektur beim Loslassen sicher), Fenster-Lookups laufen über einen O(1)-Index, und Folge-Apps erhalten während des Ziehens einen kurzen Accessibility-Messaging-Timeout, sodass eine einzelne ausgelastete App Tiley nicht mehr mitten im Ziehen blockieren kann.
- Bei aktiven verknüpften Gruppen oder Gruppierungs-Badges lasen Gruppenoperationen Fensterpositionen weit häufiger neu als nötig: Das Bilden, Auflösen oder erneute Validieren einer Gruppe tastete die Position jedes geöffneten Fensters per synchroner Accessibility-Lesevorgänge mehrfach pro Ereignis ab (ein einzelner Klick auf ein gekoppeltes Fenster konnte sechs bis acht vollständige Durchläufe auslösen), und Badge-Aktualisierungen tasteten bei jedem Fokuswechsel alle Fenster ab. Alle diese Pfade lesen jetzt nur noch die tatsächlich beteiligten Fenster (Gruppenmitglieder und Badge-Kandidaten), sodass der Accessibility-Verkehr pro Ereignis nicht mehr mit der Gesamtzahl der offenen Fenster skaliert.
- Das Anwenden eines Layouts blockiert die App nicht mehr. Die Fensterbewegungs-Sequenz (die zwischen den Accessibility-Schritten bewusst wartet, um Apps auszusitzen, die Positionen zurücksetzen) lief bisher seriell auf dem Main-Thread — ein Vier-Fenster-Preset blockierte Tiley 200 ms oder länger, plus rund 100 ms pro App für die Anhebe-Sequenz. Bewegungen laufen jetzt auf Hintergrund-Threads, unabhängige Fenster werden parallel bewegt, die Anhebe-Wartezeiten blockieren den Main-Thread nicht mehr, und schnell aufeinanderfolgende Anwendungen werden in Reihenfolge abgearbeitet. Das Timing der Accessibility-Schritte pro Fenster ist unverändert.
- Die Fenster→Space-Abfrage stellte bei jeder Fensterlisten-Aktualisierung (d. h. nach jedem App-Wechsel) eine WindowServer-Anfrage pro Fenster. Space-Zuordnungen haben jetzt einen kurzlebigen Cache (maximal fünf Sekunden, bei Space-Wechseln verworfen), und der Monitor für über Spaces verteilte Gruppen — der den Cache bewusst umgeht — prüft alle zwei Sekunden statt jede Sekunde.
- Sidebar-Zeilen lösten ihre Gruppenlink-Partner bei jedem Renderdurchlauf mit linearen Scans und Bundle-ID-Abfragen pro Zeile neu auf, und ein Cache-Fehler ließ die App-Namens-Abfrage des Suchfelds bei den meisten Apps jedes Mal die Info.plist von der Festplatte neu lesen (das negative Ergebnis wurde nie gespeichert). Die Partner-Auflösung endet jetzt sofort für Fenster ohne Links und nutzt indizierte Abfragen; beide Namens-Caches speichern auch negative Ergebnisse.
- Der erste Fensterwechsel-Tastendruck nach dem Öffnen des Overlays sowie die Zielauflösung auf einigen Pfaden führten weiterhin eine vollständige synchrone Accessibility-Aufzählung aller offenen Fenster auf dem Main-Thread aus — bei vielen Fenstern ein Stillstand von über 100 ms. Beide verwenden jetzt die beim Öffnen bereits an der Live-Fensterreihenfolge ausgerichtete Liste wieder und greifen nur dann auf eine synchrone Erfassung zurück, wenn gar keine Liste existiert (Erststart); die autoritative Hintergrund-Aktualisierung gleicht kurz darauf ab.
- Bei Multi-Display-Setups tastete jeder Bildschirm ohne das Menüleisten-Statussymbol sein Hintergrundbild bei jedem Renderdurchlauf neu ab, um die Textfarbe der Miniatur-Menüleiste zu bestimmen — pro Durchlauf wurde das Bild gerastert und ein Histogramm über rund 50.000 Pixel berechnet. Die abgetastete Farbe wird jetzt pro Bildschirm zwischengespeichert und nur neu berechnet, wenn sich das Hintergrundbild oder die Bildschirmkonfiguration ändert.
- Bei registrierten Satelliten-Verknüpfungen fragte jedes Bewegungs- oder Größenänderungs-Ereignis eines beliebigen Fensters Launch Services einmal pro registriertem App-Bundle ab, bevor überhaupt geprüft wurde, ob das bewegte Fenster Teil eines Paars ist — während eines Fenster-Drags viele Male pro Sekunde. Die Relevanzprüfung läuft jetzt zuerst mit günstigen ID-Vergleichen, und die Bundle-Abfrage erfolgt nur noch bei Ereignissen, die tatsächlich ein verknüpftes Paar betreffen.
- Die Dropdown-Buttons der Aktionsleiste (Display-Verschieben / Größe ändern) erzwangen bei jedem SwiftUI-Update-Durchlauf — in Hover- oder Tastendruck-Frequenz — ein vollständiges AppKit-Neuzeichnen, und jedes Neuzeichnen tönte die SF-Symbol-Bilder neu ein, indem es die Bitmaps kopierte und neu renderte. Die Buttons zeichnen jetzt nur noch neu, wenn sich eine tatsächlich verwendete Eingabe ändert, und eingefärbte Symbolbilder werden pro Symbol, Größe, Tönung und Erscheinungsbild zwischengespeichert (Themenwechsel rendern weiterhin frische Farben).
- Die Gruppierungs-Badge-Panels wurden bei jeder Badge-Aktualisierung vollständig neu gerendert — jede Aktualisierung baute den SwiftUI-View-Baum jedes Badges neu auf und setzte dessen Panel-Rahmen neu, selbst wenn sich nichts geändert hatte. Badges vergleichen sich jetzt mit ihrem vorherigen Zustand und überspringen das Neu-Rendern, wenn Position, Zustand und Hover-Flags unverändert sind.
- Massen-Fensteraktionen (alle Fenster einer App oder eines ganzen Bildschirms auf ein anderes Display verschieben, mehrere Fenster schließen, Apps ausblenden) planten pro betroffenem Fenster eine vollständige Aktualisierung der Fensterliste. Diese werden jetzt zu einer einzigen verzögerten Aktualisierung zusammengefasst, sodass die Kosten nach der Aktion unabhängig von der Fensteranzahl konstant bleiben.
- Jeder Start aus dem Programme-Ordner spawnte synchron `hdiutil info` (das Hunderte von Millisekunden dauern kann) auf dem Main-Thread, um zu prüfen, ob noch ein Tiley-Diskimage eingehängt ist — und führte bei einem Fund ein zweites `hdiutil` aus, nur um einen Pfad aufzulösen, den die erste Abfrage bereits geliefert hatte. Die Erkennung läuft jetzt im Hintergrund und kehrt nur bei einem tatsächlich gefundenen Image auf den Main-Thread zurück; die redundante zweite Abfrage entfällt, und auch die Auswerfen/Papierkorb-Bereinigung nach dem Neustart blockiert den Start nicht mehr.
- Das Einstellungsfenster löste bei jedem Renderdurchlauf — jedem Tick beim Ziehen der Raster-Schieberegler — die Identitäts-Fingerabdrücke der angeschlossenen Displays neu auf und baute den Standard-Preset-Satz neu. Beides ist jetzt memoisiert und wird nur neu berechnet, wenn sich die Bildschirmkonfiguration oder die Rastergröße tatsächlich ändert.
- Das Bearbeiten eines Presets (Umbenennen, App-Zuweisung, Rechteck-Bearbeitung) hob bei jeder Änderung sämtliche globalen Preset-Hotkeys auf und registrierte sie neu — Umsortieren ebenso. Hotkeys werden jetzt nur neu registriert, wenn eine Bearbeitung tatsächlich die Kurzbefehle eines Presets berührt; Umsortieren und neu erstellte Presets überspringen dies vollständig.
- Bei aktiviertem Debug-Log öffnete, ergänzte und schloss jede Logzeile die Logdatei — was genau die vermessenen Hochfrequenz-Pfade I/O-gebunden machte. Das Datei-Handle wird jetzt einmal geöffnet und wiederverwendet.
- Die Größenänderungs-Schaltfläche der Seitenleiste las bei jedem SwiftUI-Renderdurchlauf (bei jedem Hover, Tastendruck oder Preset-Hover, einmal pro Display) die Fensterposition über einen synchronen Bedienungshilfen-Aufruf an die Ziel-App aus und ermittelte jedes Mal das App-Symbol. Eine beschäftigte Ziel-App konnte das Overlay bei jedem Durchlauf ausbremsen. Die Fensterposition wird jetzt nur noch einmal beim tatsächlichen Öffnen des Größenmenüs gelesen, das Symbol kommt aus dem Fenster-Cache, und die Liste der auf den Bildschirm passenden Größen-Presets wird pro Bildschirmgröße zwischengespeichert.
- Jeder Ziehbeginn im Raster – und jedes Verlassen und Zurückkehren des Zeigers – riss das bildschirmfüllende Layout-Vorschaufenster ab und erzeugte ein neues (ein frisches NSWindow samt Hosting-View und bildschirmgroßem Backing Store); beim Ziehen außerhalb des Rasters schrieb zudem jedes Mausereignis den Zustand des ausgewählten Presets neu und ließ das Overlay auf allen Displays im Takt der Mausereignisse neu rendern. Das Vorschaufenster bleibt jetzt erhalten, solange Tileys Oberfläche offen ist, und wird nur beim Schließen des Overlays oder bei geänderter Bildschirmkonfiguration freigegeben; das Ziehen außerhalb des Rasters meldet den Übergang nur einmal, und unveränderte Preset-Auswahl-Schreibvorgänge werden übersprungen.
- Die Modellschicht ermittelte App-Symbole und Bundle-IDs bei jedem SwiftUI-Renderdurchlauf und bei jedem Rasterzellenwechsel über Launch Services (Mini-Desktop-Fenstervorschau, Live-Layoutvorschau und Preset-Hover, das alle offenen Fenster zweimal durchlief), und da jede Abfrage ein neues Symbolobjekt lieferte, konnten die Vorschauansichten nie als unverändert erkannt werden. Diese Abfragen laufen jetzt über einen Cache pro Prozess (beim Beenden des Prozesses verworfen), sodass gleiche Eingaben gleiche Werte liefern und die Ansichten das Neurendern überspringen; das Vorschaufenster fordert außerdem nicht mehr bei jedem Zellenwechsel erneut das In-den-Vordergrund-Holen an.
- Tiley beobachtet alle Fenster auf Verschieben und Größenänderungen, um „Gruppe bilden“-Badges anbieten zu können, und las bei jedem solchen Ereignis Position und Größe des Fensters über zwei synchrone Bedienungshilfen-Aufrufe aus der App zurück – und verwarf das Ergebnis. Jedes Ziehen eines Fensters in irgendeiner App kostete daher pro Ereignis zwei Roundtrips in die gezogene App. Dieses Lesen entfällt; die Benachrichtigungen für Fokus- und Hauptfensterwechsel (beide werden bei einem einzigen Klick ausgelöst) stoßen die Anhebungsverknüpfung jetzt einmal statt zweimal an, und die App-weiten Benachrichtigungen werden pro App statt pro Fenster registriert.
- Bei jedem App-Wechsel (Cmd-Tab oder Klick in eine andere App) lief eine WindowServer-Fensterlistenabfrage samt vollständiger Neusortierung von Tileys zwischengespeicherter Fensterliste, deren Ergebnis nie angezeigt wurde (das Overlay richtet den Cache beim Öffnen ohnehin neu aus), und 200 ms später erfolgte eine synchrone Bedienungshilfen-Abfrage an die gerade aktivierte App – auch wenn gar keine Fenstergruppen existierten –, sodass eine nicht reagierende App Tiley bis zum sechssekündigen Standard-Timeout blockieren konnte. Die überflüssige Neuausrichtung entfällt, die Gruppenprüfung läuft jetzt vor jedem Bedienungshilfen-Aufruf, das Berechtigungs-Flag wird nur bei tatsächlicher Änderung geschrieben, und Tiley setzt nun prozessweit ein Bedienungshilfen-Timeout von einer Sekunde, damit eine hängende App Tiley nicht mehr sekundenlang blockieren kann.
- Beim Loslassen eines Fensters nach dem Verschieben oder Vergrößern – in jeder App – las Tiley Position und Größe jedes offenen Fensters über synchrone Bedienungshilfen-Aufrufe zurück (zwei pro Fenster, im Hauptthread), um zu prüfen, ob das bewegte Fenster nun ein anderes berührt. Bei 30–40 Fenstern waren das 60–80 Roundtrips pro Ziehvorgang, und derselbe Durchlauf konnte pro Geste zweimal laufen. Die Erkennung liest jetzt nur noch die bewegten Fenster sowie die sichtbaren Fenster, deren aktuelle Grenzen in deren Nähe liegen (ermittelt mit einer einzigen Fensterlistenabfrage), und der Beruhigungstimer wird neu gestellt statt bei jedem Bewegungsereignis neu erzeugt.
- Nach dem Anwenden eines Layouts wurden die von Tiley gerade platzierten Fenster manchmal so behandelt, als hätte der Benutzer sie von Hand verschoben: Die verzögert eintreffenden Bedienungshilfen-Benachrichtigungen der Apps kamen erst an, nachdem die Unterdrückung von Tileys eigenen Bewegungen geendet hatte, sodass die Nachbarschaftsprüfung für manuelle Bewegungen über alle Fenster auf dem Bildschirm lief und „Gruppe bilden“-Badges zwischen einem platzierten Fenster und einem dahinterliegenden, nicht verwandten Fenster mit zufällig übereinstimmender Kante anzeigte – eine frisch gruppierte Kante konnte so ein zusätzliches Link-Badge zeigen. Tiley merkt sich jetzt die Rahmen der von ihm platzierten Fenster, sodass diese verzögerten Benachrichtigungen als Echo der eigenen Bewegungen erkannt werden.
- Mehrere kleine Arbeiten pro Renderdurchlauf des Overlay-Fensters wurden bei jedem Hover, Tastendruck oder Ziehen einmal pro Display wiederholt: Die Anzeigenamen aller Bildschirme wurden für die Seitenleisten-Überschriften jedes Mal erneut beim Display-Treiber abgefragt, Hintergrundbild-Metadaten und der Vorschau-Bildschirm wurden drei- bis viermal neu aufgelöst, das gerade bearbeitete und das gerade überfahrene Preset wurden für das Raster bis zu neunmal nachgeschlagen, jedes Preset-Vorschaubild durchsuchte pro Zelle alle seine Rechtecke, und sobald irgendeine Fenstergruppe oder ein Satellitenpaar existierte, baute jede Seitenleistenzeile ihre eigenen Nachschlagetabellen für die Link-Badges neu auf. Anzeigenamen werden jetzt zwischengespeichert, Bildschirm-, Hintergrundbild- und Preset-Eingaben werden einmal pro Durchlauf aufgelöst, die Seitenleiste baut ihre Link-Nachschlagetabellen einmal und teilt sie über alle Zeilen, und die Preset-Vorschaubilder vergleichen ihre Eingaben und überspringen das Neuzeichnen, wenn sich nichts geändert hat.
- Das Overlay konnte nach einem Klick auf das Fenster einer anderen App auf dem Bildschirm bleiben. Unter macOS 14 und neuer kann das System es ablehnen, Tiley zur aktiven App zu machen, wenn der Hotkey unmittelbar nach der Interaktion mit einer anderen App gedrückt wird (etwa direkt nach dem Klick auf ein anderes Fenster, um das vorherige Overlay zu schließen); das Overlay war dann sichtbar, ohne dass Tiley aktiv war, sodass ein Klick anderswo nie die Deaktivierung auslöste, die es ausblendet. Tiley prüft die Aktivierung jetzt kurz nach dem Anzeigen des Overlays und wiederholt sie – und falls sie weiterhin verweigert wird, blendet ein Klick außerhalb der Tiley-Fenster das Overlay direkt aus.
- Jede Fensterlistenerfassung (im Hintergrund nach jedem App-Wechsel und bei jedem Öffnen des Overlays) führte pro Fenster drei bis vier separate Bedienungshilfen-Roundtrips aus – Unterrolle, Position, Größe und später der Titel – und holte pro Fenster die Liste der laufenden Apps erneut, erzeugte ein neues Bedienungshilfen-App-Element und zählte die Bildschirme neu auf. Außerdem kopierte sie die Liste der sichtbaren Fenster zweimal, nur um Show Desktop / Mission Control zu prüfen. Die Attribute jedes Fensters werden jetzt in einem einzigen Roundtrip geholt, App-Liste, App-Elemente und Bildschirmliste werden einmal pro Erfassung gesammelt, und die beiden Exposé-Prüfungen teilen sich eine Fensterlistenkopie.
- Fenstergruppen-Operationen führten dieselbe Arbeit mehrmals pro Benutzeraktion aus: Das Auflösen einer Gruppe löste eine vollständige Neuvalidierung aller anderen Gruppen (mit erneutem Lesen jedes Mitgliedsrahmens über die Bedienungshilfen) plus eine Badge-Aktualisierung aus, und das erneute Verknüpfen von Satelliten oder eine Space-Aufteilung löste zwei oder mehr Gruppen nacheinander auf – ein einziger Klick auf ein gekoppeltes Fenster konnte so vier bis fünf Badge-Aktualisierungen und sieben bis acht Fensterlistenabfragen auslösen; Verknüpfen, Trennen, ablaufende Kandidaten und geschlossene Fenster starteten jeweils eine eigene sofortige Aktualisierung; das Anwenden eines Layouts trennte Bildschirmrand-Nachbarschaften einzeln mit je einer vollen Aktualisierung; und ein einzelner Klick erreichte den Gruppen-Raise-Handler bis zu dreimal. Mehrfach-Auflösungen validieren jetzt einmal am Ende, die abschließenden Aktualisierungen werden auf den nächsten Run-Loop-Durchlauf zusammengefasst, die Neuvalidierung reicht ihre bereits gelesenen Rahmen an die Aktualisierung weiter, die Trennung vor dem Layout teilt die Gruppe einmal ohne Zwischenaktualisierung, und wiederholte Raise-Aufrufe für dasselbe Fenster innerhalb von 100 ms werden verworfen.
- Ein einziger Versionszähler steuerte jede von der Fensterliste abhängige Ansicht im Overlay und wurde sowohl bei Auswahl- als auch bei Listenänderungen erhöht: Ein einzelnes Öffnen des Overlays erhöhte ihn vier- bis fünfmal, jeder Klick in der Seitenleiste zweimal, und jede Erhöhung leerte zudem den App-Cache der Seitenleiste (Symbol, Bundle-ID, Originalname), sodass das nächste Rendern die App jeder Zeile erneut über Launch Services auflöste und ihre Info.plist neu las. Die Hintergrundaktualisierung nach dem Öffnen veröffentlichte die Liste außerdem erneut, selbst wenn sie mit der bereits angezeigten identisch war. Auswahländerungen erhöhen jetzt einen separaten Zähler, den nur die auswahlabhängigen Ansichten beobachten, der App-Cache wird nur ungültig, wenn sich die Menge der Apps tatsächlich ändert, und eine Aktualisierung mit identischer Liste veröffentlicht sie nicht mehr erneut.
- Mehrere Gruppenaktionen blockierten den Hauptthread weiterhin mit der synchronen Fensterverschiebungssequenz (die bewusst zwischen den Bedienungshilfen-Schritten wartet): Das Füllen einer Gruppe bis zum Bildschirmrand wartete mindestens 50 ms pro Mitglied, das Tauschen zweier Fenster und das Angleichen ihrer Ausdehnung ebenso, und jeder Satellitenwechsel stellte die Ankerposition – plus bis zu vier Drift-Nachprüfungen – auf dieselbe Weise wieder her, sodass ein Badge-Klick oder Satellitenwechsel Tiley 100–250 ms (bis zu einer Sekunde, wenn eine App den Rahmen ablehnt) einfrieren konnte. Das Bestätigen eines einzelnen Fensters mit Enter pumpte die Run-Loop ebenfalls 50 ms lang, und beim Bestätigen auf eine ausgeblendete App blieb das Overlay während der 150-ms-Einblendewartezeit sichtbar. Diese Verschiebungen laufen jetzt in Hintergrundthreads, der Gruppenzustand wird nach dem Landen aktualisiert (und die Unterdrückung der Gruppenkopplung bis dahin gehalten statt fixe 0,1 s), die Einzelfenster-Bestätigung wartet durch Aussetzen statt Pumpen, und Tileys Fenster verlassen den Bildschirm vor der Einblendewartezeit.
- Nach dem Angleichen der Höhen (oder Breiten) zweier verknüpfter Fenster konnte das Ziehen eines der beiden das Paar versetzt zurücklassen, wenn die App das Ziehen als gleichzeitiges Verschieben und Vergrößern meldete (wie macOS beim Auflösen der Kachelung eines bildschirmfüllenden Fensters): Der Partner wird aufgefordert, der senkrechten Verschiebung zu folgen, manche Apps ignorieren das jedoch, und das Einrasten beim Loslassen, das die gemeinsamen Kanten wieder ausrichten sollte, entschied anhand von Caches, die die vorangehende Lücken-/Überlappungsauflösung gerade mit dem Live-Rahmen des Partners überschrieben hatte, ob die Kanten „gemeinsam“ waren – und kam zu dem Schluss, sie seien es nicht. Die gemeinsamen Kanten werden jetzt beim Beginn des Ziehens aufgezeichnet, und das Einrasten beim Loslassen verwendet diese Aufzeichnung.
- Das Überfahren einer Zeile in der Fenster-Seitenleiste des Overlays wertete den gesamten Overlay-Body dieses Displays neu aus – die Bildschirmkomposition, das Raster mit seinen Miniaturfenstern, jede Preset-Zeile und die Hinweisleiste –, weil der Zeilen-Hover-Zustand in der obersten Ansicht lag. Die Zeilenliste der Seitenleiste ist jetzt eine eigene Ansicht, die diesen Hover-Zustand besitzt, sodass beim Bewegen des Zeigers über die Liste nur noch die Zeilen neu gerendert werden.
- Zwei weitere Kosten pro Renderdurchlauf im Overlay: Das Bewegen des Zeigers über das Raster verglich jede Basiszelle neu (bis zu 144, jede mit einem Durchlauf der Auswahlen), weil die überfahrene Zelle eine Eingabe des gesamten Zellrasters war, und jede Neuauswertung des Overlay-Bodys – ein Preset-Hover, eine Auswahländerung, ein Tastendruck – baute die Zeilenliste der Seitenleiste und ihre Link-Nachschlagetabellen von Grund auf neu, obwohl sich ihre Eingaben nicht geändert hatten. Die Basiszellen sind jetzt eine eigene, wertverglichene Ansicht mit der Hover-Füllung als einzelnem Overlay, und die Seitenleistenzeilen und Nachschlagetabellen werden anhand von Fensterliste, Suchtext, Spaces, Bildschirmkonfiguration und Gruppenzustand zwischengespeichert.

### Entfernt

- Eine interne Statusmeldung, die bei jeder Layout-Aktion geschrieben, aber nirgends in der Oberfläche angezeigt wurde (ein Überbleibsel einer früheren Oberfläche), wurde zusammen mit ihren elf nun ungenutzten Lokalisierungsschlüsseln in allen Sprachen entfernt. Keine sichtbaren Verhaltensänderungen.

## [5.2.1] - 2026-07-31

### Behoben

- Behoben: Zwischengespeicherte Hintergrundbilder werden jetzt auf die Vorschauauflösung des Overlays heruntergerechnet, statt in voller Desktop-Foto-Auflösung im Speicher zu bleiben. Dadurch sinken belegter und maximaler Speicher beim Öffnen von Tiley mit großen benutzerdefinierten Hintergrundbildern deutlich, ohne die Platzierung des Hintergrundbilds oder die Erkennung der Menüleistenfarbe zu verändern.

## [5.2.0] - 2026-07-31

### Behoben

- Behoben: Das App-Symbol von Tiley sah dem Symbol des am weitesten verbreiteten Desktop-Betriebssystems zu ähnlich.
- Behoben: Zwischengespeicherte Hintergrundbilder von getrennten oder neu konfigurierten Displays konnten im Speicher verbleiben, bis sich die Version des Desktop-Bildes änderte. Tiley verwirft den Hintergrundbild-Cache jetzt sofort bei Änderungen der Bildschirmkonfiguration und reduziert so unnötigen Speicherverbrauch nach dem Anschließen, Trennen oder Neuordnen von Monitoren.
- Behoben: Nach dem Herunterladen eines Updates konnte Sparkles Dialog „Installieren und neu starten" hinter dem Einstellungsfenster verschwinden. Die Wiederherstellung des Einstellungsfensters lief im Sparkle-Callback `didFinishUpdateCycleFor`, doch dieser feuert bereits, wenn der Appcast-Prüfzyklus endet — also direkt nachdem der/die Nutzer:in im ersten Dialog auf „Update installieren" geklickt hat, lange bevor der Download fertig ist und der Installations-/Neustart-Dialog erscheint. Das Einstellungsfenster wurde so vor diese noch aktiven Dialoge gezogen. Die Wiederherstellung wartet nun auf `standardUserDriverWillFinishUpdateSession`, sobald Sparkle benutzerseitige UI gezeigt hat; `didFinishUpdateCycleFor` stellt das Einstellungsfenster nur noch bei wirklich stillen Hintergrundprüfungen ohne Sparkle-Dialog wieder her.
- Behoben: Wurde direkt nach dem Öffnen von Tiley ein Layout angewendet, konnten die Fenster noch in der Reihenfolge vor der Aktualisierung ausgewählt werden. Die Fensterliste der Seitenleiste wird zunächst aus dem Cache befüllt und erst ersetzt, wenn die maßgebliche Erfassung im Hintergrund eintrifft — ein in dieser Lücke ausgelöstes Preset-Kürzel oder ein Klick in der Layout-Vorschau wählte seine Ziele daher aus der veralteten Reihenfolge. Die Layout-Anwendung wartet jetzt auf die aktualisierte Fensterliste und läuft dann gegen diese; Tileys eigene Fenster werden sofort ausgeblendet, damit sich die Bedienung weiterhin flott anfühlt.
- Beim Öffnen von Tiley konnten die Miniaturfenster in der Mini-Desktop-Vorschau kurzzeitig an veralteten Positionen erscheinen und sprangen erst ein bis zwei Sekunden später an die richtige Stelle, sobald die asynchrone Fenstererfassung abgeschlossen war. Das erste Bild wird aus der zwischengespeicherten Fensterliste gezeichnet, die nur die Koordinaten vom Zeitpunkt ihrer Erstellung enthält — Fenster, die bei geschlossener Tiley-Oberfläche verschoben oder in der Größe geändert wurden, erschienen daher an ihrer alten Position. Die Cache-Neuausrichtung vor dem Anzeigen aktualisiert nun aus demselben schnellen CGWindowList-Schnappschuss, der bereits für die Z-Reihenfolge verwendet wird, auch die Koordinaten (und den zugehörigen Bildschirm) jedes Fensters, sodass die Miniaturfenster vom ersten Bild an ihre aktuellen Positionen zeigen.

## [5.1.9] - 2026-05-12

### Behoben

- Behoben: Beim Start von Tiley erschien gelegentlich ein Tiley-Symbol im Dock (ohne den laufenden Prozess-Punkt), obwohl „Dock-Symbol anzeigen" deaktiviert war. Ursache war eine versteckte SwiftUI-Anker-`Window`-Szene, die während des Starts kurzzeitig ein 0×32 pt großes Fenster bei macOS registrierte — lange genug, um vor dem Wechsel auf `.accessory` einen Dock-Eintrag entstehen zu lassen. Die Anker-Szene wurde entfernt; die Aktivierungsrichtlinie wird jetzt ausschließlich von `applicationWillFinishLaunching` und der bestehenden `applyDockIconVisibility`-Logik verwaltet.

## [5.1.8] - 2026-05-09

### Behoben

- Bei gruppierten Fenstern mit deckungsgleicher Ober- und Unterkante bleibt die Höhe nun auch beim Vergrößern bündig, nicht mehr nur beim Verkleinern. Der Frame-Setter des Folgefensters setzte zuerst die Größe und dann die Position; ein Vergrößern, das das Fenster oben über die Menüleiste bzw. den Bildschirmrand drücken würde, wurde von der App stillschweigend gedeckelt — die Unterkante folgte dem Drag, aber die Oberkante driftete nach unten. Der Setter bewegt das Folgefenster jetzt zunächst an seine geplante Endposition und setzt erst dann die neue Größe; ein abschließender Positions-Fixup auf Basis der von der App tatsächlich akzeptierten Größe hält die Kontaktkante auch dann stabil, wenn Min-/Max-Beschränkungen greifen. Beim Loslassen der Drag-Geste rastet ein zusätzlicher Snap-Schritt die laut Cache eigentlich bündigen Ober-/Unter- bzw. Links-/Rechtskanten ein und korrigiert so jede verbliebene Pixel-Abweichung gegenüber der Quelle.

## [5.1.7] - 2026-05-08

### Entfernt

- Der Fallback, der den Hintergrund der Mini-Bildschirme im Layout-Raster bei Hintergrundbildtypen ohne eigenes Vorschaubild (Fotos-Mediathek, Aerial usw.) aus dem BMP-Cache des Wallpaper-Agents unter `~/Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches/` füllte, wurde entfernt. Der Cache liegt im Container von `com.apple.wallpaper.agent`, und unter macOS Sequoia löst der Zugriff darauf den neuen Berechtigungsdialog "App-Daten" aus — eine viel zu hohe Anforderung für ein rein kosmetisches Hintergrundbild. Tiley stützt sich jetzt ausschließlich auf die öffentliche Schreibtischbild-URL und `/System/Library/Desktop Pictures/.thumbnails/`. Lässt sich das Hintergrundbild über keine dieser Quellen auflösen, wird es weggelassen und nur Raster, Füllfarbe und Bildschirm-Layout gezeichnet.

## [5.1.6] - 2026-05-08

### Behoben

- Beim ersten Start auf einem frischen Mac erscheint kein überflüssiger Berechtigungsdialog "Tasteneingaben empfangen" (Eingabeüberwachung) mehr. Der Dialog wurde dadurch ausgelöst, dass Tiley einen `CGEventTap` für die Mausklick-Überwachung anlegte, bevor die Bedienungshilfen-Berechtigung erteilt war. Der Tap wird jetzt erst in dem Moment erstellt, in dem die Bedienungshilfen-Freigabe erfolgt; macOS behandelt die Tap-Erstellung dann als von der bestehenden Bedienungshilfen-Zustimmung gedeckt und überspringt die Eingabeüberwachungs-Abfrage komplett.
- Nach dem erstmaligen Erteilen der Bedienungshilfen und der Rückkehr zu Tiley füllen sich die Fensterliste in der Seitenleiste und das Layout-Raster jetzt sofort, statt im Zustand "Keine Fenster" zu verharren. Zuvor wurde der Fensterlisten-Cache bereits ohne Bedienungshilfen mit einem leeren Ergebnis befüllt und nach der Freigabe als verbindlich behandelt; der Cache-Refresh wird nun ohne Bedienungshilfen übersprungen, und der Rückkehrpfad nach der Freigabe aktiviert das Layout-Raster explizit und stößt eine frische Erfassung an.

## [5.1.5] - 2026-05-08

### Behoben

- Das Fenstergruppierungs-Badge (der schwebende Kreis zwischen verknüpften Fenstern) liegt nicht mehr über Sheets und modalen Dialogen, die von derselben Anwendung präsentiert werden. Erkannt werden Fokusfenster mit der Subrolle `AXDialog` / `AXSystemDialog`, der Rolle `AXSheet` sowie übergeordnete Fenster mit angehängtem Sheet; solange eine dieser Bedingungen zutrifft, wird das Badge ausgeblendet und erscheint erst wieder, wenn der modale Dialog geschlossen ist.

## [5.1.4] - 2026-05-03

### Behoben

- Wenn ein Fensterpaar explizit aus einer Gruppe gelöst, anschließend auseinandergezogen und wieder mit den Kanten zusammengeführt wird, erscheint nun erneut ein "Gruppe bilden"-Kandidaten-Badge. Zuvor stoppte das Gruppe-Lösen die Accessibility-Beobachtung der nun isolierten Fenster, sodass nachfolgende manuelle Bewegungen die Ereignisse, die die Nachbarschaftserkennung antreiben, nicht mehr auslösten — das Badge tauchte stillschweigend nicht mehr auf, bis ein anderer Auslöser (Space-Wechsel, App-Aktivierung usw.) die Fensterlisten-Cache-Aktualisierung erneut anstieß.

## [5.1.3] - 2026-04-27

### Behoben

- Das Einstellungsfenster wird nun in der Mitte des gesamten Bildschirms geöffnet statt im Zentrum des sichtbaren Bereichs ohne Dock. Es erscheint damit unabhängig von der Position des Docks in der tatsächlichen Bildschirmmitte.

## [5.1.2] - 2026-04-26

### Behoben

- Zwischen bereits verknüpften Fenstern erscheint kein „Gruppe bilden"-Kandidaten-Badge mehr — weder zwischen Paaren, die nach einem Preset zufällig aneinanderstoßen, noch zwischen Paaren aus zwei unterschiedlichen bestehenden Gruppen, noch zwischen Paaren, die über den Satelliten-Mechanismus eines app-zugewiesenen Presets verbunden sind.
- Badges verknüpfter Gruppen erscheinen nur noch für die Gruppe, die das vorderste Fenster enthält (oder transitiv über Satelliten daran angeschlossen ist). Badges unbeteiligter Hintergrundgruppen, die nur zufällig die App des fokussierten Fensters teilen, werden nicht mehr eingeblendet.
- Das Anheben eines gruppierten Fensters — per Klick, per Auswahl in der Tiley-Sidebar und Enter oder über macOS' Click-to-activate — bringt die ganze Gruppe nun zuverlässig gemeinsam nach vorn. Mehrere Fälle, in denen ein Geschwisterfenster zuvor hinter einem anderen Fenster verborgen blieb, sind behoben (Fenster fremder Apps, die zwischen Gruppenmitgliedern eingeklemmt waren; das vorher als Hauptfenster gemerkte Fenster derselben App, das vor das ausgewählte Fenster gehoben wurde; Tileys eigene Wiederherstellung der ausgelagerten Fenster, die als manueller Drag missdeutet wurde).

### Geändert

- Beim Anwenden eines Layout-Presets, dessen gruppiertes Paar ein Fenster betrifft, das bereits Teil einer bestehenden Gruppe ist, werden nicht mehr alle Fenster in eine einzige größere Gruppe zusammengeführt. Das gemeinsame Fenster wird zu einem „Fenster-Anker" und jeder seiner Partner (die anderen Mitglieder der bestehenden Gruppe sowie der neu hinzugefügte Partner) wird als Satellit registriert — analog zum bereits für app-zugewiesene Preset-Slots verwendeten Modell. Jedes Paar behält sein eigenes gespeichertes Layout: Ein Klick auf einen Satelliten holt den Anker nach vorn und stellt die gespeicherten Positionen dieses Paars wieder her; ein Klick auf den Anker bringt denjenigen Satelliten in den Vordergrund, der derzeit am weitesten vorn ist. Beispiel: Bei einer bestehenden A↔B-Gruppe lässt das Anwenden eines Presets, das C↔A paart, A↔B intakt — ein Klick auf B bringt A im ursprünglichen A↔B-Layout neben B zurück, ein Klick auf C bringt A im Preset-Layout neben C. Das aktive Paar zeigt das verknüpfte Badge wie zuvor; das Wechseln zwischen Satelliten baut die räumliche Gruppe dynamisch um

## [5.1.1] - 2026-04-25

### Hinzugefügt

- Im Hover-Menü des Verknüpfungs-Badges einer Fenstergruppe gibt es jetzt eine dritte Schaltfläche neben der Tausch-Schaltfläche: **Fensterhöhe angleichen** (für links/rechts angeordnete Paare, Symbol: Auf-/Abwärtspfeile) bzw. **Fensterbreite angleichen** (für oben/unten angeordnete Paare, Symbol: Links-/Rechtspfeile). Damit werden die beiden Seiten des Badges (alle Gruppenmitglieder, jeweils anhand der Kontaktlinie zugeordnet) auf der senkrechten Achse aneinander angeglichen. Mit „beide Seiten" sind nicht nur die zwei direkt vom Badge verbundenen Fenster gemeint, sondern **alle Gruppenmitglieder auf derselben Seite der Kontaktlinie** — auch „Geschwister", die zwar nicht direkt miteinander verknüpft sind, aber an derselben Elternkante hängen (Beispiel: oben `[A]`, unten `[B]` `[C]`, beide an A's Unterkante – nicht jedoch direkt miteinander verknüpft → ein Klick auf „Breite angleichen" am A↔B-Badge behandelt `{B, C}` als eine Seite und macht B+C zusammen genauso breit wie A). Innerhalb jeder Seite werden die Fenster sortiert und kantenbündig neu angeordnet: die äußersten Kanten verankern an der äußeren Hülle, benachbarte Fenster treffen sich am Mittelpunkt ihrer ursprünglichen Kanten — saubere gemeinsame Kanten bleiben unverändert, eine Lücke oder Überlappung wird gleichmäßig auf beide Seiten verteilt geschlossen. Die Schaltfläche wird ausgeblendet, wenn beide Seiten bereits ausgerichtet sind und es auch innen keine Lücke / Überlappung gibt
- „Gruppe bilden"-Vorschlags-Badges erscheinen jetzt auch, wenn Sie ein Fenster manuell verschieben oder dessen Größe ändern, sodass dessen Kante an die Kante eines anderen Fensters anschließt — nicht nur nach dem Anwenden eines Tiley-Layouts. Das Badge erscheint in dem Moment, in dem Sie die Maus loslassen (während des Ziehens/Vergrößerns selbst bleibt es ausgeblendet); ein Klick darauf verbindet das Paar zu einer Fenstergruppe, genau wie das Badge nach dem Layout-Anwenden
- Beim Klick auf ein „Gruppe bilden"-Vorschlags-Badge wird das Hover-Menü (Gruppierung aufheben / Tauschen / Höhe oder Breite angleichen) im selben Moment angezeigt, in dem die Gruppe entsteht — Sie müssen den Cursor nicht erst vom Badge wegbewegen und wieder darüber führen
- Das Hover-Menü (Aktions-Pille) wird jetzt sanft ein- und ausgeblendet, statt schlagartig zu erscheinen oder zu verschwinden. Während des Ausblendens behält das Badge-Panel seine erweiterte Größe, damit die Pille nicht abgeschnitten wird; ein erneutes Überfahren während der Animation bricht das Einklappen ab
- Im Hover-Menü eines verknüpften Badges gibt es zwei neue Schaltflächen: **Bildschirmbreite ausfüllen** (Symbol `rectangle.portrait.arrowtriangle.2.outward`) und **Bildschirmhöhe ausfüllen** (Symbol `rectangle.arrowtriangle.2.outward`). Sie skalieren proportional alle Fenster der Gruppe, sodass deren Begrenzungsrechteck die sichtbare Bildschirmbreite bzw. -höhe (ohne Dock und Menüleiste) genau ausfüllt — die relativen Abstände zwischen den Mitgliedern bleiben erhalten. Die jeweilige Schaltfläche wird ausgeblendet, wenn die Gruppe auf dieser Achse bereits den Bildschirm ausfüllt
- Wenn man mit dem Mauszeiger über das Verknüpfungs-Badge zwischen zwei gruppierten echten Fenstern fährt, erscheint jetzt ein kleines Aktionsmenü unter dem Badge (oder darüber, wenn unten kein Platz auf dem Bildschirm ist): eine **Gruppierung aufheben**-Schaltfläche und eine Schaltfläche zum Tauschen der Fenster — **Linkes/rechtes Fenster tauschen** oder **Oberes/unteres Fenster tauschen** je nach Anordnung des Paares. Das Badge selbst dient nicht mehr als Aufheben-Schaltfläche, sondern nur noch als visueller Hinweis auf die bestehende Verknüpfung. Beim Tauschen werden alle anderen Verknüpfungen, die diese beiden Fenster zu dritten Fenstern haben, gelöst, sodass nach dem Tausch eine saubere Zwei-Fenster-Gruppe übrig bleibt

### Behoben

- Beim Anwenden eines Mehr-Rechteck-Layout-Presets wird die Breite oder Höhe des Nachbarfensters jetzt automatisch angepasst, wenn ein Fenster aufgrund der Mindestgröße der App nicht auf sein Ziel-Rechteck verkleinert werden kann, sodass die gemeinsame Kante ausgerichtet bleibt (Preset-Abstand wird beibehalten). Bisher kam es zu Überlappungen oder versetzten Lücken
- Die Gruppierungsanzeige in der Seitenleiste zeigt jetzt auch App-Slot-Satellitenverknüpfungen an, die nicht Teil der aktuell aktiven räumlichen Gruppe sind. Wird ein Preset mit App-zugewiesenen Rechtecken und gruppierten Paaren angewendet, wird das Fenster auf der nicht zugewiesenen Seite über die Bundle-ID der zugewiesenen App als Satellit registriert. Wendet man dasselbe Preset (oder ein anderes mit derselben Anker-App) erneut mit einem anderen Fenster an, fällt das vorherige Paar aus der räumlichen `WindowGroup` heraus, die Satelliten-Verknüpfung (Mitführung beim Klick) bleibt jedoch erhalten. Bisher waren solche „im Hintergrund weiter aktiven" Verknüpfungen in der Seitenleiste nicht sichtbar — jetzt werden sie zusammen mit den aktiven räumlichen Partnern als Partner-App-Symbole angezeigt und lassen sich per Hover → Klick einzeln lösen. Dies gilt auch dann, wenn ein Fenster Satellit mehrerer Anker-Apps ist oder wenn der Bundle-ID eines Anker-Fensters mehrere Satelliten zugeordnet sind

### Geändert

- Beim Anwenden eines Layout-Presets, das ein Fenster bündig an einen Bildschirmrand schiebt, werden nur noch die Gruppen-Verbindungen an genau jener Bildschirmrand-Seite des angepassten Fensters gelöst — Verbindungen an anderen Kanten bleiben erhalten. Beispiel: Bei einem horizontalen Paar A↔B und einem vertikalen Paar A↔C löst „Bildschirmbreite ausfüllen" auf A die A↔B-Verknüpfung (da die rechte Kante von A zur rechten Bildschirmkante wird), während A↔C erhalten bleibt, solange A's Unterkante den Bildschirmboden nicht erreicht. Bisher löste eine Tiley-Größenänderung, die nur einen Teil einer Gruppe betraf, unabhängig von der Kante stets die gesamte Gruppe auf
- Die Gruppierungsanzeige in der Seitenleiste wurde neu gestaltet: Statt eines schwebenden Link-Symbols zwischen den Zeilen werden in jeder gruppierten Fensterzeile rechts — direkt vor dem Index-Symbol — die App-Symbole aller verknüpften Partnerfenster nebeneinander angezeigt. Beim Überfahren eines Partner-Symbols wird die Zeile des Partnerfensters in der Seitenleiste hervorgehoben, und gleichzeitig wechselt dieses Symbol (sowie das entsprechende Symbol in der Partnerzeile) in einen roten `x`-Zustand, sodass auf einen Blick klar ist, welche beiden Fenster betroffen sind. Ein Klick im `x`-Zustand löst nur diese eine Verbindung — bei einem Fenster mit mehreren Verknüpfungen lassen sich die Links so einzeln lösen. Der Platz für das Index-Symbol bleibt immer reserviert, damit Zeilen auch ohne Index sauber ausgerichtet bleiben

## [5.1.0] - 2026-04-25

### Hinzugefügt

- Neue Standard-Layout-Voreinstellung „Mitte": ein 4×4-Raster mit der mittleren 2×2-Region ausgewählt, gebunden an die Tastenkombination `C`
- Neue "+"-Zeile am Ende der Layout-Voreinstellungsliste. Ein Klick erstellt eine neue Voreinstellung namens "Neue Layout-Voreinstellung" und wechselt sofort in den Bearbeitungsmodus
- Gruppierungen lassen sich jetzt direkt beim Bearbeiten einer Layout-Voreinstellung festlegen: An jeder gemeinsamen Kante zwischen zwei Bereichen erscheint ein `link.badge.plus`-Abzeichen. Ein Klick markiert das Paar als Gruppe (das Abzeichen wechselt in den verbundenen Zustand; beim Darüberfahren erscheint ein Aufhebungs-Symbol). Auch beim Überfahren einer Voreinstellung in der Seitenleiste werden die verbundenen Kanten als Abzeichen auf der Vorschau angezeigt, damit auf einen Blick erkennbar ist, welche Bereiche gruppiert werden. Beim Anwenden der Voreinstellung sind die entsprechenden Fenster von Anfang an gruppiert — kein zusätzlicher Klick nötig
- Rechtecke einer Layout-Voreinstellung können jetzt an eine bestimmte Anwendung gebunden werden. Im Voreinstellungseditor zeigt jedes Rechteck ein `macwindow.badge.plus`-Abzeichen — ein Klick öffnet eine Liste laufender Anwendungen (oder über "Andere Anwendung…" den Dateisystem-Browser). Zugewiesene Rechtecke werden als Miniaturfenster mit dem App-Symbol statt mit einer Indexnummer dargestellt; ein Klick auf das beim Überfahren eingeblendete × hebt die Zuweisung auf. Beim Anwenden der Voreinstellung landet im zugewiesenen Rechteck stets das vorderste Fenster der gebundenen App (die App wird bei Bedarf gestartet und bis zu 30 Sekunden lang auf ein Fenster gewartet). Läuft die App, hat aber keine Fenster, wird eine Systembenachrichtigung gepostet. Wenn bei einem gruppierten Paar genau eine Seite zugewiesen ist, wird das Fenster, das in der nicht zugewiesenen Seite landet, sitzungsweit als "Satellit" mit dem Fenster der zugewiesenen App verknüpft: ein Klick auf eines bringt auch das andere nach vorne

### Geändert

- `debugLog` wurde mit `@autoclosure` versehen, sodass bei deaktivierter Debug-Protokollierung keinerlei Kosten für die String-Interpolation der Log-Nachrichten anfallen

### Behoben

- Verknüpfungs-Badges für Fenstergruppen erscheinen nicht mehr auf Fenstern, die vollständig hinter einem anderen Fenster verborgen sind. Nach dem Anwenden eines Layouts auf viele Fenster werden Badges nur noch zwischen sichtbaren (vorderen) Fenstern angezeigt; verdeckte Fenster werden aus den Gruppierungskandidaten ausgeschlossen, bis sie in den Vordergrund gebracht werden

### Entfernt

- Die nach dem Anwenden eines Layouts automatisch hinzugefügte temporäre Voreinstellung "Letzte Auswahl" wurde entfernt. Neue Voreinstellungen werden jetzt explizit über die "+"-Zeile erstellt

## [5.0.1] - 2026-04-23

### Behoben

- Behoben: Beim Zurückwechseln zu einer App mit Cmd+Tab flackerte ein gruppiertes Fenster kurz in den Vordergrund. Die Z-Order-Verknüpfung wurde ausgelöst, bevor macOS das Anheben der App-Fenster abgeschlossen hatte, wodurch ein nicht fokussiertes Gruppenmitglied kurz vor dem fokussierten erschien

## [5.0.0] - 2026-04-22

### Hinzugefügt

- Fenstergruppierung hinzugefügt. Nach dem Anwenden einer Layout-Voreinstellung mit mehreren Fenstern erscheint an der Mitte jeder aneinandergrenzenden Kante ein Link-Abzeichen (`link.badge.plus`). Ein Klick auf das Abzeichen gruppiert die Fenster, sodass das Ziehen eines Fensters alle Mitglieder gemeinsam bewegt, das Größenändern der gemeinsamen Kante das gegenüberliegende Fenster entgegengesetzt skaliert und das Hervorheben eines Mitglieds die anderen direkt darunter anhebt. Beim Darüberfahren erscheint ein Auflösungssymbol; ein Klick darauf löst die Gruppe auf. Beim Schließen eines beteiligten Fensters wird die Gruppe automatisch aufgelöst
- Link-Abzeichen in der Seitenleiste: In der Seitenleiste des Hauptfensters wird nun zwischen aneinandergrenzenden gruppierten Fenstereinträgen ein kleines Link-Symbol angezeigt, sodass auf einen Blick erkennbar ist, welche Fenster verknüpft sind. Würde ein gruppiertes Fenster sonst durch einen App-Kopfzeilenblock von seinem Partner getrennt werden, wird es aus diesem Block herausgelöst und direkt unter seinen Partner platziert, damit die Verbindung sichtbar bleibt

### Behoben

- Behoben, dass Hover- und Zieh-Vorschauen auf dem Hauptfenster-Raster auch bei der normalen Layout-Anwendung den Stil aus der Voreinstellungsbearbeitung verwendeten (eingefärbtes Rechteck, keine Titelleiste); außerhalb der Voreinstellungsbearbeitung wird nun korrekt das Miniaturfenster mit App-Symbol, App-Name und Fenstertitel angezeigt
- Behoben, dass eines von zwei Fenstern gelegentlich an der falschen Position landete, wenn ein Seite-an-Seite-Layout auf eine Mehrfachauswahl angewendet wurde: Die Animation, die verdeckende Fenster vorübergehend nach unten verschiebt, um das ausgewählte Fenster sichtbar zu machen, lief nach dem Anwenden des Layouts weiter und überschrieb so die neu gesetzten Positionen
- Behoben, dass ein Fenster nach dem Anwenden eines Seite-an-Seite-Layouts langsam nach rechts unten driftete. Die verzögerte Aufräum-Routine nach dem Ausblenden des Hauptfensters konnte eine Wiederherstellungs-Animation starten, während das frisch platzierte Fenster noch in der Liste der beiseite geschobenen Fenster stand, und zog es dadurch langsam zurück zu seiner Ursprungsposition vor der Verdrängung

## [4.4.3] - 2026-04-20

### Geändert

- Beim Bearbeiten einer Layout-Voreinstellung verwenden Hover- und Zieh-Vorschauen auf dem Raster jetzt denselben Rechteck-Stil wie bestätigte Auswahlen: in der Farbe des nächsten Index und mit der zugehörigen Indexnummer mittig, ohne Titelleiste und ohne Löschen-Schaltfläche. Zusätzlich zeigt das Darüberfahren mit der Maus über eine leere Zelle ein ein Zellen großes Vorschaurechteck an, auch wenn bereits andere Layouts registriert sind
- Beim Bearbeiten einer Voreinstellung zeigen nun sowohl das Hover- als auch das Zieh-Rechteck die nach dem Bestätigen zugewiesene Indexnummer mittig an (passend zum bestätigten Rechteck, in das sie übergehen) – einschließlich der ein Zellen großen Hover-Vorschau. Vorschauen von Layout-Voreinstellungen (Darüberfahren mit der Maus über eine Voreinstellung in der Seitenleiste, Vollbild-Vorschau-Overlay beim Anwenden von Mehrfachauswahl-Voreinstellungen) zeigen weiterhin Indexnummern an

### Behoben

- Das Hauptfenster sprang in die Bildschirmmitte, wenn bei aktivierter Option „Beim Klick neben dem Symbol anzeigen" ein Raster in einer Layout-Voreinstellung hinzugefügt oder bearbeitet wurde; das Fenster bleibt jetzt nahe am Menüleistensymbol verankert
- Behoben, dass bestätigte Auswahlrechtecke gelegentlich ohne Füllung und Rahmen angezeigt wurden (nur Schließen-Schaltfläche und Indexnummer sichtbar), wenn eine Layout-Voreinstellung mehrere Auswahlen enthielt

## [4.4.2] - 2026-04-19

### Behoben

- Beim Anwenden einer Anordnung auf mehrere ausgewählte Fenster war die Stapelreihenfolge umgekehrt; das zuerst ausgewählte (primäre) Fenster liegt nun wie erwartet ganz oben

## [4.4.1] - 2026-04-18

### Geändert

- Beim Öffnen per Tastenkürzel wird nun die Miniatur-Bildschirmvorschau – nicht das gesamte Fenster – auf dem Display zentriert. Als Referenz dient der gesamte Bildschirmrahmen (inkl. Menüleiste und Dock), sodass die Miniaturansicht auch bei seitlich platziertem Dock zentriert bleibt
- Wenn „Bei Klick nahe dem Symbol anzeigen" aktiviert ist, wird beim Klicken auf das Menüleistensymbol nun die Mitte der Miniatur-Bildschirmvorschau (und nicht die des gesamten Fensters) am Symbol ausgerichtet; der Sprechblasen-Pfeil zeigt weiterhin direkt auf das Symbol

## [4.4.0] - 2026-04-17

### Geändert

- Miniatur-Fenstervorschauen im Raster verbessert: Beim Hover und Ziehen werden nun getönte Miniaturfenster statt einfarbiger Rechtecke angezeigt, sekundäre Bildschirme zeigen den gleichen Miniaturfensterstil wie der primäre Bildschirm, und Rasterzellen bleiben beim Ziehen sichtbar
- Overlay auf Nicht-Ziel-Bildschirmen vereinfacht: Das Miniatur-Bildschirmanordnungssymbol wurde entfernt und nur ein großer zentrierter Richtungspfeil wird angezeigt
- Rasterinteraktionen auf sekundären Bildschirmfenstern reagieren nun auf den ersten Klick, ohne dass ein zusätzlicher Klick zum Fokussieren erforderlich ist

### Behoben

- Das Sprechblasen-Dreieck verschwand und das Fenster verschob sich nach oben, bevor die Ausblend-Animation begann, wenn Tiley durch Klick auf das Menüleistensymbol geschlossen wurde. Das Dreieck bleibt nun während des Ausblendens sichtbar, wie beim Schließen durch Klick auf ein anderes Fenster
- Das Sprechblasen-Dreieck wurde fälschlicherweise auch auf Fenstern sekundärer Bildschirme angezeigt, wenn Tiley über das Menüleistensymbol geöffnet wurde
- Werkzeugleistenschaltflächen waren beim Start deaktiviert, wenn die Fensterliste bereits vor dem Erscheinen der Seitenleistenansicht verfügbar war

## [4.3.9] - 2026-04-14

### Hinzugefügt

- Sprechblasen-Pfeilspitze an der zur Menüleiste bzw. zum Dock-Symbol zeigenden Kante des Hauptfensters hinzugefügt, wenn "Beim Klicken nahe dem Symbol anzeigen" aktiviert ist

### Behoben

- Problem behoben, bei dem unmittelbar nach einem App-Wechsel — bevor der Hintergrund-Fensterlisten-Cache aktualisiert wurde — beim Öffnen von Tiley kurz die zuvor vorderste App oben in der Seitenleiste erschien oder gelegentlich ein Fenster ausgewählt wurde, das nicht das vorderste war

## [4.3.8] - 2026-04-13

### Hinzugefügt

- Sanfte Ein-/Ausblendanimation beim Anzeigen und Ausblenden des Overlay-Fensters mittels GPU-beschleunigter Core Animation

### Behoben

- Symbolleisten-Schaltflächen waren beim ersten Start deaktiviert, bis die Fensterauswahl in der Seitenleiste geändert wurde

## [4.3.7] - 2026-04-10

### Geändert

- Öffnungsgeschwindigkeit des Overlay-Fensters deutlich verbessert. Aufwendige Operationen (Accessibility-/CoreGraphics-Abfragen, Layout-Vorschau-Aufbau) werden nun erst nach dem Fensteraufbau ausgeführt, und die vorab zwischengespeicherte Fensterliste wird sitzungsübergreifend beibehalten

## [4.3.6] - 2026-04-10

### Hinzugefügt

- Option hinzugefügt, das Tiley-Fenster beim Klick neben dem Menüleisten- oder Dock-Symbol anzuzeigen (standardmäßig aktiviert)

## [4.3.5] - 2026-04-09

### Behoben

- Inkonsistenter Eckenradius des Miniaturfensters auf dem Mini-Bildschirm bei Hover- und Drag-Vorschauen behoben, sodass er nun mit der statischen Fenstervorschau übereinstimmt

## [4.3.4] - 2026-04-09

### Behoben

- Einstellungsfenster wird vor der Sparkle-Updateprüfung geschlossen, damit die Rastervorschau beim Hover das Fenster nicht in den Vordergrund bringt und Sparkle-Dialoge verdeckt. Das Einstellungsfenster wird nach Abschluss des Updatezyklus wiederhergestellt

## [4.3.3] - 2026-04-09

### Hinzugefügt

- Das Fenster kann jetzt durch Ziehen der Tastaturhinweisleiste, der Menüleisten-/Dock-Bereiche des Minibildschirms, leerer Seitenleistenbereiche und Lücken in der Symbolleiste verschoben werden

### Behoben

- Ziehen im oberen Bereich des Rasters verschob das Fenster statt Zellen auszuwählen

## [4.3.2] - 2026-04-08

### Behoben

- Fehler behoben, bei dem nach einem Fensterwechsel beim sofortigen Aufrufen von Tiley zwei Fenster ausgewählt werden konnten

## [4.3.1] - 2026-04-07

### Behoben

- Einstellungsfenster wird nun ausgeblendet, wenn Sparkle den Update-Dialog anzeigt, sodass die Rastervorschau beim Hover das Einstellungsfenster nicht mehr in den Vordergrund bringt und die Schaltfläche „Installieren und Neustarten" blockiert

## [4.3.0] - 2026-04-07

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
