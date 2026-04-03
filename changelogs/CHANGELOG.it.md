# Registro delle modifiche

## [Unreleased]

## [4.1.2] - 2026-04-03

### Aggiunto

- Badge con indice dell'ordine di selezione visualizzati a destra degli elementi finestra nella barra laterale quando sono selezionate due o più finestre

### Modificato

- L'elenco delle finestre nella barra laterale viene ora pre-memorizzato in background tramite listener di eventi del workspace (attivazione, avvio e chiusura delle app), in modo da apparire istantaneamente all'apertura dell'overlay
- Migliorato il comportamento dell'evidenziazione per gli elementi della barra laterale raggruppati per applicazione. L'intestazione dell'app viene mostrata come selezionata solo quando tutte le sue finestre sono selezionate, e passando il mouse sull'intestazione vengono evidenziati sia l'intestazione che tutte le finestre figlie
- Migliorato il comportamento di uscita dallo schermo intero: ora imposta direttamente l'attributo AXFullScreen (con pressione del pulsante come fallback), attendendo fino a 2 secondi per il completamento dell'animazione

### Corretto

- Risolto il problema per cui l'overlay non si apriva quando l'applicazione in primo piano non ha finestre. Ora viene mostrato un messaggio "Nessuna finestra" e il trascinamento viene disabilitato
- Risolto il problema per cui il desktop del Finder veniva trattato come una finestra ridimensionabile. Quando il desktop è in primo piano, viene ora selezionata la finestra reale del Finder più in primo piano, oppure viene mostrato "Nessuna finestra" se non ne esistono
- Corretto il problema per cui l'overlay non si apriva quando l'applicazione in primo piano non aveva finestre (ad es. Finder senza finestre aperte, app solo barra dei menu); ora viene utilizzata la finestra visibile più in alto sullo schermo
- Corretta la posizione della finestra che non veniva applicata correttamente su display non principali per alcune app (es. Notion). Aggiunta verifica della posizione con logica di ritentativo dopo il ridimensionamento per gestire le app che ripristinano la posizione in modo asincrono

## [4.1.1] - 2026-03-31

### Modificato

- La scorciatoia predefinita per selezionare la finestra successiva è stata cambiata da Tab a Space; la finestra precedente da Shift+Tab a Shift+Space
- Le finestre spostate ora tornano sempre alla posizione originale con animazione alla chiusura dell'overlay

## [4.1.0] - 2026-03-31

### Aggiunto

- Cambio finestra con tasti modificatori tenuti premuti (stile Cmd+Tab): dopo aver aperto l'overlay, tieni premuti i tasti modificatori e premi ripetutamente il tasto di attivazione per scorrere le finestre; rilascia i tasti modificatori per portare la finestra selezionata in primo piano; premi le scorciatoie locali del layout mentre tieni premuti i tasti modificatori per applicare il layout corrispondente
- Sezione riconoscimenti per le licenze di terze parti nelle Impostazioni (Sparkle, TelemetryDeck)

### Modificato

- I pannelli Impostazioni e Autorizzazioni sono ora finestre separate a livello normale (non flottante), in modo che le finestre di aggiornamento di Sparkle e altre finestre di sistema possano essere visualizzate sopra
- La barra laterale è ora sempre visibile; il pulsante mostra/nascondi è stato rimosso
- Il pulsante delle impostazioni è stato spostato dalla barra inferiore all'estremità sinistra della barra delle azioni nella barra laterale
- L'anteprima mini schermo ora ha angoli arrotondati su tutti e quattro i lati indipendentemente dal tipo di display
- La barra del titolo della finestra in miniatura ora mostra il nome dell'applicazione insieme al titolo della finestra
- Il badge "Aggiornamento disponibile" è stato sostituito con un punto rosso sul pulsante delle impostazioni e un tooltip; nel pannello delle impostazioni viene mostrato un popover sul pulsante "Verifica aggiornamenti"

## [4.0.9] - 2026-03-30

### Corretto

- Il ridimensionamento della finestra falliva e la posizione veniva spostata per alcune applicazioni: la posizione di rimbalzo quando il ridimensionamento iniziale veniva rifiutato era in fondo allo schermo (nessuno spazio per espandersi), lasciando la finestra in una posizione errata. Ora il rimbalzo avviene nella parte superiore dell'area visibile e la posizione viene ripristinata esplicitamente se il ridimensionamento continua a fallire
- Le finestre spostate a volte non venivano ripristinate nella posizione originale dopo aver selezionato una finestra in background: il ripristino cercava le finestre in un elenco potenzialmente obsoleto, causando errori. I riferimenti alle finestre vengono ora memorizzati direttamente nei dati di tracciamento dello spostamento e la pulizia viene posticipata fino al completamento dell'animazione di ripristino
- I pulsanti "Aggiungi scorciatoia" / "Aggiungi scorciatoia globale" rispondevano solo ai clic vicino al centro: padding e sfondo sono stati spostati all'interno dell'etichetta del pulsante in modo che l'intera area visibile sia cliccabile

## [4.0.8] - 2026-03-30

### Corretto

- Il pannello delle autorizzazioni non viene più visualizzato sopra altre app e finestre di dialogo del sistema durante la richiesta di accesso all'accessibilità
- L'anteprima dello sfondo non veniva visualizzata su macOS Tahoe 26.4: adattamento al cambiamento di struttura del plist dello Store sfondi (`Desktop` → chiave `Linked`), gli sfondi Foto vengono caricati dalla cache BMP dell'agente sfondi, aggiunto il valore di posizionamento `FillScreen` (sostituto di `Stretch` su Tahoe), e abilitate le impostazioni della modalità di visualizzazione per i fornitori di sfondi non di sistema
- Le modalità di visualizzazione centrata e a mosaico renderizzavano le immagini troppo piccole quando i metadati DPI dell'immagine non erano 72 (ad es. screenshot Retina a 144 DPI); ora vengono sempre utilizzate le dimensioni reali in pixel

## [4.0.7] - 2026-03-29

### Corretto

- La modalità di visualizzazione a mosaico dello sfondo non veniva riflessa nell'anteprima del mini schermo (il valore di posizionamento "Tiled" dal plist dello Store sfondi di macOS non veniva abbinato correttamente)
- Aggiunta registrazione di debug per la pipeline di risoluzione dello sfondo per aiutare a diagnosticare problemi di visualizzazione

## [4.0.6] - 2026-03-29

### Aggiunto

- Passando il cursore su un preset multi-layout, vengono mostrati i numeri di indice del layout sulla griglia mini-schermo, sull'anteprima a dimensione reale e sulla lista finestre della barra laterale, rendendo immediatamente chiaro quale layout viene applicato a ciascuna finestra indipendentemente dalla percezione dei colori

### Modificato

- Interfaccia della finestra di impostazioni ottimizzata per adattarsi al look & feel di macOS Tahoe: pulsanti della barra degli strumenti e della barra delle azioni unificati con forma a capsula e sfondi hover/pressione adattivi al sistema, schede sezione impostazioni con sfondo grigio chiaro senza bordo, toggle ridimensionati alla dimensione di Preferenze di Sistema, e lista scorciatoie ristrutturata con una sezione indipendente "Scorciatoie spostamento display"

### Corretto

- Le finestre della barra laterale che superano il numero di layout del preset ora mostrano correttamente il colore dell'ultimo layout invece del colore di selezione principale

## [4.0.5] - 2026-03-29

### Corretto

- Le finestre spostate per mostrare la finestra di destinazione selezionata ora vengono ripristinate correttamente alla posizione originale anche durante la navigazione rapida
- L'anteprima del ridimensionamento di una singola finestra era troppo tenue rispetto alle anteprime del layout multi-finestra; ora utilizza la stessa opacità

## [4.0.4] - 2026-03-29

### Aggiunto

- Al passaggio del mouse su un preset, l'anteprima del mini-schermo mostra le barre del titolo delle finestre (icona app, nome app, titolo finestra)

### Modificato

- La barra del titolo dell'anteprima layout a dimensione reale ora mostra il nome dell'app insieme al titolo della finestra (formato: "Nome App — Titolo Finestra")

## [4.0.3] - 2026-03-29

### Aggiunto

- I preset con layout multipli ora ridimensionano più finestre anche con una sola finestra selezionata, utilizzando l'ordine Z effettivo (la finestra più in primo piano per prima)
- Quando le finestre selezionate sono meno delle definizioni di layout, la finestra selezionata viene sempre trattata come principale e gli slot rimanenti vengono riempiti per ordine Z
- Al passaggio del mouse su un preset con layout multipli, le righe delle finestre interessate nella barra laterale vengono evidenziate con i colori del layout (blu, verde, arancione, viola)

## [4.0.2] - 2026-03-29

### Modificato

- L'anteprima del layout a dimensioni reali ora mostra solo le anteprime per il numero di selezioni definite nel preset (le finestre selezionate in eccesso rispetto al numero di selezioni del preset non vengono più visualizzate)

## [4.0.1] - 2026-03-29

### Modificato

- La palette dei colori di selezione ora cicla tra blu, verde, arancione e viola (4 colori), in modo che la 5ª selezione corrisponda alla 1ª
- I preset predefiniti (Metà sinistra/destra/superiore/inferiore) ora includono la metà opposta come selezione secondaria

## [4.0.0] - 2026-03-29

### Aggiunto

- Preset di layout a selezione multipla: definisci più aree della griglia per preset per posizionare finestre diverse in posizioni diverse
  - Ogni trascinamento nell'editor dei preset aggiunge una nuova selezione (1ª, 2ª, 3ª, ...)
  - Ogni selezione mostra il suo numero di indice e un pulsante di eliminazione
  - La sovrapposizione delle selezioni viene impedita (con feedback visivo)
  - Quando si applica un preset a selezione multipla, le finestre vengono assegnate per ordine di selezione: la prima finestra selezionata ottiene la selezione 1, la successiva la selezione 2, ecc.
  - Le miniature e le anteprime a dimensione reale mostrano tutte le selezioni con colori indicizzati
  - Le selezioni della griglia hanno un margine di 1pt dai bordi dello schermo per una migliore visibilità

### Modificato

- L'ordine delle finestre multiple ora segue l'ordine di selezione anziché l'ordine Z della barra laterale
  - La prima finestra selezionata è sempre la principale; le finestre aggiunte con Cmd+clic vengono aggiunte in ordine
  - La selezione per intervallo con Shift+clic mantiene la finestra di ancoraggio come principale
  - Influisce sull'applicazione dei preset, sul portare in primo piano (Invio) e sulla visualizzazione dell'anteprima

## [3.4.0] - 2026-03-28

### Aggiunto

- Selezione multipla delle finestre nella barra laterale con azioni in blocco
    - Clic sull'intestazione dell'app per selezionare tutte le sue finestre
    - Cmd+clic per aggiungere/rimuovere finestre singole
    - Shift+clic per selezionare un intervallo continuo di finestre
- Azioni in blocco per la selezione multipla: porta in primo piano (mantenendo l'ordine Z della barra laterale), ridimensiona/sposta nella griglia, sposta su un altro display, chiudi/esci
- Quando si chiudono più finestre selezionate, le app con tutte le finestre selezionate vengono chiuse (eccetto il Finder)

### Modificato

- Cliccando sull'intestazione di un'app nella barra laterale ora si selezionano tutte le finestre di quell'app (in precedenza veniva selezionata solo la finestra in primo piano)
- Selezionando una finestra all'interno di un gruppo di app, l'intestazione dell'applicazione rimane evidenziata
- Per le app non-Finder con più finestre, nella barra delle azioni viene mostrato un pulsante "Esci dall'app" accanto a "Chiudi finestra"
- Il tooltip "Chiudi finestra" ora mostra il nome della finestra (es.: Chiudi "Documento")

## [3.3.2] - 2026-03-28

### Aggiunto

- I tasti di scelta rapida per "Seleziona finestra successiva", "Seleziona finestra precedente", "Porta in primo piano" e "Chiudi/Esci" sono ora configurabili nella sezione scorciatoie delle preferenze
- Nuova voce di menu contestuale "Chiudi le altre finestre di [App]" facendo clic destro su una finestra nella barra laterale (visibile solo quando l'app ha più finestre)

### Modificato

- La sezione di configurazione delle scorciatoie è stata riorganizzata in due gruppi: scorciatoie per le azioni sulle finestre e scorciatoie per lo spostamento del display
- Le scorciatoie per lo spostamento del display sono ora solo globali; il supporto per le scorciatoie locali e le relative opzioni di configurazione sono stati rimossi
- Su macOS 26 (Tahoe), i pulsanti della barra degli strumenti, il pulsante Esci, i pulsanti della barra delle azioni e il pulsante del menu a discesa utilizzano ora l'effetto Liquid Glass interattivo, in conformità con le Human Interface Guidelines
- Il colore di sfondo della finestra ora usa il colore di sistema per una migliore compatibilità con le modifiche all'aspetto di macOS
- Le finestre spostate tornano ora alla posizione originale con un'animazione quando si conferma una selezione, si applica un layout o si annulla con Escape

## [3.3.1] - 2026-03-28

### Aggiunto

- Quando si seleziona una finestra nella barra laterale, le finestre sovrapposte vengono spostate verso il basso con un'animazione fluida per rendere visibile la finestra selezionata senza cambiare il focus
- Viene mostrato un bordo evidenziato attorno alla finestra attualmente selezionata nella barra laterale

### Corretto

- Corretto l'ordine di navigazione Tab/frecce per corrispondere all'ordine di visualizzazione della barra laterale (raggruppato per spazio, schermo e applicazione)
- Le finestre spostate vengono ripristinate alla loro posizione originale quando la selezione viene annullata (Esc) o Tiley viene chiuso

## [3.3.0] - 2026-03-27

### Corretto

- Correzione preventiva dell'utilizzo eccessivo della CPU che poteva verificarsi in ambienti multi-display
- Correzione di un ciclo di ridisegno dell'icona della barra di stato che poteva causare un utilizzo della CPU al 100% quando veniva visualizzato un badge sovrapposto (notifica di aggiornamento o indicatore di debug)
- Le finestre di Tiley ora fluttuano sempre sopra le finestre normali per non essere nascoste durante il cambio con Tab

## [3.2.9] - 2026-03-27

### Corretto

- Corretto l'ordine di navigazione Tab/frecce per corrispondere all'ordine di visualizzazione della barra laterale (raggruppato per spazio, schermo e applicazione)

## [3.2.8] - 2026-03-26

### Corretto

- Corretto il problema nella barra laterale in cui Tab/frecce alternavano solo tra due finestre invece di scorrere tutte le finestre

## [3.2.7] - 2026-03-26

### Corretto

- Corretto un arresto anomalo che si verificava all'avvio come elemento di login (correzione incompleta nella versione 3.2.6)

## [3.2.6] - 2026-03-26

### Corretto

- Corretto un arresto anomalo che si verificava all'avvio come elemento di login

## [3.2.5] - 2026-03-26

### Modificato

- Sezioni scorciatoie e scorciatoie globali unificate in un'unica sezione
- Interfaccia di impostazione delle scorciatoie unificata per tutti i tipi

### Corretto

- Risolto un problema per cui la finestra principale poteva rimanere visibile quando l'app passava in background
- Corretto il bordo di evidenziazione tagliato dagli angoli arrotondati e dal notch sui display integrati (ora viene disegnato sotto l'area della barra dei menu)

## [3.2.4] - 2026-03-26

### Aggiunto

- Aggiunte scorciatoie per spostare le finestre tra gli schermi (principale, successivo, precedente, scegli dal menu, schermo specifico)

## [3.2.3] - 2026-03-25

### Aggiunto

- Aggiunti indicatori freccia direzionali al pulsante e alle voci di menu "Sposta su display", che mostrano visivamente la direzione del display di destinazione in base alla disposizione fisica degli schermi
- Quando la finestra selezionata si trova su un altro display, l'overlay a griglia mostra ora una freccia direzionale e un'icona della disposizione degli schermi al centro, guidando l'utente verso la posizione della finestra

### Modificato

- Regolato l'aspetto quando è disponibile un aggiornamento

## [3.2.2] - 2026-03-25

### Aggiunto

- La selezione di una finestra nella barra laterale la porta temporaneamente in primo piano per facilitarne l'identificazione; l'ordine originale viene ripristinato quando si passa a un'altra finestra o si annulla
- L'anteprima di ridimensionamento ora mostra una barra del titolo con l'icona dell'applicazione e il titolo della finestra, rendendo più intuitivo identificare quale finestra si sta disponendo

## [3.2.1] - 2026-03-25

### Corretto

- Corretta la barra laterale che non mostrava finestre in ambienti multi-schermo perché il filtro degli spazi considerava solo lo spazio attivo di un singolo display

## [3.2.0] - 2026-03-25

### Aggiunto

- Quando sono presenti più spazi Mission Control, la barra laterale mostra solo le finestre dello spazio attuale
- L'overlay a griglia ora mostra un'anteprima della finestra in miniatura con pulsanti semaforo, icona dell'app e titolo della finestra nella posizione attuale della finestra di destinazione

### Modificato

- La scomparsa dell'overlay è ora più reattiva durante l'applicazione dei layout o il passaggio in primo piano delle finestre
- Le finestre in modalità schermo intero nativa di macOS vengono ora automaticamente riportate alla modalità normale prima del ridimensionamento

## [3.1.1] - 2026-03-24

### Corretto

- Corretta la visualizzazione a mosaico anziché a riempimento delle miniature degli sfondi di sistema
- Corretta l'immagine errata per gli sfondi dinamici; aggiunto supporto miniature per gli sfondi basati su provider Sequoia, Sonoma, Ventura, Monterey e Macintosh
- Il testo della barra dei menu nell'anteprima della griglia si adatta ora alla luminosità dello sfondo (nero su sfondi chiari, bianco su scuri, come in macOS)

## [3.1.0] - 2026-03-24

### Modificato

- Sostituiti i menu kebab (…) al passaggio del mouse nella lista finestre con menu contestuali nativi macOS (clic destro)
- Aggiunti pulsanti di azione (Sposta sullo schermo, Chiudi/Esci, Nascondi altre app) accanto al campo di ricerca della barra laterale
- Le miniature della griglia delle preimpostazioni di layout ora riflettono le proporzioni dell'area utilizzabile dello schermo (escludendo barra dei menu e Dock), adattandosi all'orientamento verticale o orizzontale.

### Corretto

- Corretto un problema per cui il ridimensionamento delle finestre talvolta falliva quando si spostava una finestra su un altro schermo (in particolare su un monitor verticale più alto), introducendo un meccanismo di nuovo tentativo per gli spostamenti tra schermi

### Rimosso

- Rimossi i pulsanti del menu kebab e di chiusura al passaggio del mouse dalle righe della barra laterale (sostituiti da menu contestuali e barra delle azioni)

## [3.0.1] - 2026-03-23

### Aggiunto

- Quando si porta una finestra in primo piano tramite Invio o doppio clic, la finestra viene spostata sullo schermo in cui si trova il puntatore del mouse, se diverso. La finestra viene riposizionata per adattarsi allo schermo e ridimensionata solo se necessario.

### Modificato

- Prestazioni di visualizzazione dell'overlay migliorate di circa l'80% grazie al pooling/riutilizzo dei controller, al caricamento differito della lista delle finestre e al rendering prioritario dello schermo di destinazione
- Rinominata l'impostazione interna del log di debug da `useAppleScriptResize` a `enableDebugLog` per riflettere meglio il suo scopo

### Corretto

- Corretto il ridimensionamento della finestra che falliva silenziosamente sullo schermo principale per alcune app (es. Chrome). Il meccanismo di rimbalzo utilizzato per gli schermi secondari viene ora applicato anche allo schermo principale
- Corretto: il clic sull'icona della barra dei menu con l'overlay visibile ora chiude l'overlay (come ESC) invece di aprire la finestra principale

## [3.0.0] - 2026-03-23

### Aggiunto

- Integrazione dell'SDK TelemetryDeck per statistiche d'uso rispettose della privacy (apertura overlay, applicazione layout, applicazione preset, modifica impostazioni)
- Le finestre nella barra laterale sono raggruppate per schermo e per applicazione; le app con più finestre mostrano un'intestazione con le righe rientrate
- Le intestazioni dello schermo nella barra laterale hanno un menu con le azioni "Raccogli finestre" e "Sposta finestre su" per gestire le finestre tra schermi
- Menu dell'intestazione app con "Sposta tutte le finestre su un altro schermo", "Nascondi altre" e "Esci"
- Menu delle app a finestra singola con "Sposta su un altro schermo", "Nascondi altre" e "Esci"
- Gli schermi vuoti (senza finestre) sono mostrati nella barra laterale con la loro intestazione

### Modificato

- Lo sfondo della griglia ora riflette accuratamente le impostazioni di visualizzazione dello sfondo macOS (riempimento, adattamento, allungamento, centro e mosaico), inclusa la corretta scalatura delle tessere, il rapporto pixel fisico per la modalità centrata e il colore di riempimento per le aree letterbox
- L'anteprima della griglia di layout ora mostra la barra dei menu, il Dock e il notch, offrendo una rappresentazione più fedele dello schermo reale

### Corretto

- Corretto un problema in cui la finestra si spostava in una posizione inattesa dopo il ridimensionamento quando era già nella posizione di destinazione. Aggiramento della deduplicazione AX tramite pre-spostamento
- Ridotto lo sfarfallio durante il ridimensionamento su schermi non principali. Il ridimensionamento viene prima tentato sul posto; il rimbalzo allo schermo principale avviene solo in caso di fallimento completo
- Durante il rimbalzo allo schermo principale, la finestra viene ora posizionata sul bordo inferiore (quasi fuori schermo) anziché nell'angolo superiore sinistro, minimizzando lo sfarfallio

## [2.2.0] - 2026-03-21

### Modificato

- Le celle della griglia non selezionate sono ora trasparenti
- Le proporzioni della griglia corrispondono ora all'area visibile dello schermo (escluse barra dei menu e Dock); se la griglia risultasse troppo alta, la larghezza viene ridotta proporzionalmente per garantire la visibilità di almeno 4 preset
- Lo sfondo della griglia di layout mostra ora l'immagine del desktop (semitrasparente, angoli arrotondati)
- Le celle selezionate con trascinamento sono ora semitrasparenti, mostrando l'immagine del desktop sottostante
- L'evidenziazione al passaggio del cursore sui preset nella griglia usa ora lo stesso stile della selezione con trascinamento

### Aggiunto

- La barra laterale dell'elenco finestre viene ora visualizzata su tutti gli schermi nelle configurazioni multi-monitor, non solo sullo schermo di destinazione
- Lo stato della barra laterale (visibilità, elemento selezionato, testo di ricerca) viene sincronizzato tra tutte le finestre degli schermi
- Log di debug del ridimensionamento opzionale (`~/tiley.log`) (Impostazioni > Debug)

### Corretto

- Corretto un problema in cui il posizionamento della finestra utilizzava la geometria dello schermo obsoleta quando il Dock o la barra dei menu si mostravano/nascondevano automaticamente mentre l'overlay era aperto
- Corretto il ridimensionamento delle finestre che falliva sugli schermi non primari nelle configurazioni DPI miste; la finestra viene temporaneamente spostata sullo schermo primario per il ridimensionamento e poi posizionata nella posizione target
- Corretta la posizione non applicata dopo il ridimensionamento quando alcune app annullano silenziosamente le modifiche alla posizione (soluzione alternativa alla deduplicazione AX)
- Quando la dimensione minima della finestra di un'app impedisce la dimensione richiesta, la posizione viene ricalcolata affinché la finestra rimanga nell'area visibile dello schermo
- Eliminato lo sfarfallio visibile delle finestre quando si cambia la finestra di destinazione tra schermi; le finestre non vengono più ricreate al cambio di schermo

## [2.1.0] - 2026-03-20

### Aggiunto

- Doppio clic su una finestra nella barra laterale per portarla in primo piano e chiudere la griglia di layout
- Menu contestuale (pulsante puntini di sospensione) sulle righe delle finestre nella barra laterale con tre azioni:
  - "Chiudi altre finestre di [App]" — chiude le altre finestre della stessa app (mostrato solo quando l'app ha più finestre)
  - "Esci da [App]" — termina l'applicazione
  - "Nascondi finestre tranne [App]" — nasconde tutte le altre applicazioni (equivalente di Cmd-H), mostra l'app selezionata se era nascosta
- Le applicazioni nascoste (Cmd-H) appaiono ora nella barra laterale come voci segnaposto (solo nome dell'app) e vengono visualizzate al 50% di opacità
- Selezionando un'app nascosta (Invio, doppio clic, ridimensionamento griglia/layout) viene automaticamente mostrata e si opera sulla sua finestra in primo piano

## [2.0.3] - 2026-03-19

### Aggiunto

- Promemoria di aggiornamento discreti di Sparkle: quando un controllo in background trova una nuova versione, appare un punto rosso sull'icona della barra dei menu e etichette "Aggiornamento disponibile" accanto al pulsante ingranaggio e al pulsante "Verifica aggiornamenti" nelle impostazioni
- Se l'icona della barra dei menu è nascosta, viene mostrata temporaneamente con il badge al rilevamento di un aggiornamento e nascosta nuovamente al termine della sessione

### Modificato

- La finestra delle impostazioni viene ora nascosta quando Sparkle trova un aggiornamento (in precedenza solo all'inizio del download) e ripristinata in caso di annullamento
- Il titolo della finestra delle impostazioni è ora localizzato in tutte le lingue supportate
- Il numero di versione è stato spostato dal titolo delle impostazioni alla sezione Aggiornamenti, accanto al pulsante "Verifica aggiornamenti"

## [2.0.2] - 2026-03-19

### Aggiunto

- Pulsante di chiusura nelle righe della barra laterale delle finestre: passando il mouse sul nome di una finestra appare un pulsante × per chiuderla
- Impostazione "Esci dall'app alla chiusura dell'ultima finestra" (Impostazioni > Finestre): quando attiva (predefinito), chiudere l'ultima finestra di un'app chiude l'app; quando disattivata, viene chiusa solo la finestra
- Il tooltip del pulsante di chiusura mostra il nome della finestra; quando l'azione chiuderà l'app, mostra il nome dell'app
- Scorciatoia da tastiera "/" per chiudere la finestra selezionata (o uscire dall'app se è l'ultima finestra e l'impostazione è attiva)

## [2.0.1] - 2026-03-19

### Modificato

- Pannello impostazioni ridisegnato in stile Tahoe: sezioni con sfondo in vetro (Liquid Glass su macOS 26+), barra degli strumenti compatta con pulsanti indietro/esci e righe raggruppate in stile iOS con controlli in linea

## [2.0.0] - 2026-03-19

### Modificato

- Il menu a tendina per la selezione della finestra di destinazione è stato sostituito con un pannello laterale con Liquid Glass (macOS Tahoe); include un campo di ricerca con supporto completo IME, navigazione con tasti freccia e Tab/Maiusc+Tab, e Cmd+F per attivare/disattivare la visibilità

### Migliorato

- Le finestre nel pannello laterale sono elencate in ordine Z (dal fronte al retro) anziché raggruppate per applicazione
- Le finestre non standard (palette, barre degli strumenti, ecc.) sono state filtrate dall'elenco delle finestre di destinazione in modo da mostrare solo le finestre documento ridimensionabili

## [1.2.7] - 2026-03-18

### Migliorato

- La finestra principale viene chiusa automaticamente quando Sparkle inizia a scaricare un aggiornamento

### Corretto

- Eliminate le giunture visibili nell'anteprima dei vincoli di ridimensionamento quando le regioni di overflow (rosso) o underflow (giallo) vengono visualizzate contemporaneamente in entrambe le direzioni

## [1.2.6] - 2026-03-18

### Corretto

- Quando si ridimensiona una finestra in background della stessa applicazione tramite il ciclo Tab, la finestra viene ora portata in primo piano se risulterebbe nascosta dietro altre finestre di quella applicazione

## [1.2.5] - 2026-03-18

### Aggiunto

- Rilevamento dei vincoli di ridimensionamento delle finestre: rileva automaticamente la ridimensionabilità per asse tramite un controllo rapido a 3 livelli (non ridimensionabile → pulsante schermo intero → sonda da 1px come fallback)
- L'anteprima del layout ora mostra aree rosse dove la finestra non può espandersi e aree gialle dove non può ridursi, fornendo un feedback visivo sui vincoli di dimensione prima dell'applicazione

## [1.2.4] - 2026-03-17

### Migliorato

- Interfaccia di modifica dei preset di layout perfezionata: pulsante di eliminazione spostato accanto al pulsante di conferma, pulsanti di modifica/azione posizionati in una colonna dedicata per evitare sovrapposizioni con le scorciatoie
- La selezione della griglia è ora modificabile in modalità di modifica: trascina sulla griglia per aggiornare la posizione del preset con anteprima in tempo reale ed evidenziazione

## [1.2.3] - 2026-03-17

### Migliorato

- Perfezionamento dell'interfaccia di modifica dei preset di layout: il pulsante di eliminazione viene mostrato come overlay sull'anteprima della griglia, con dialogo di conferma, sfondo opaco al passaggio del mouse e stile dei pulsanti uniforme

## [1.2.2] - 2026-03-17

### Modificato

- Riprogettata la modifica dei preset di layout per un'esperienza di impostazione più intuitiva

## [1.2.1] - 2026-03-17

### Correzioni

- Corretto il dialogo "Sposta in Applicazioni" mostrato erroneamente invece di "Copia" durante l'avvio da un DMG scaricato (Gatekeeper App Translocation impediva il riconoscimento del percorso dell'immagine disco)

## [1.2.0] - 2026-03-17

### Aggiunto

- Cambio finestra di destinazione: premi Tab / Maiusc+Tab mentre la griglia è visualizzata per scorrere le finestre disponibili
- Menu a discesa finestra di destinazione: fai clic sull'area informazioni per selezionare una finestra da un menu a comparsa
- Tab e Maiusc+Tab sono ora tasti riservati e non possono essere assegnati come scorciatoie di layout

## [1.1.8] - 2026-03-16

### Aggiunto

- Dopo la copia da un DMG, viene offerta l'opzione di espellere l'immagine disco e spostare il file DMG nel Cestino
- Rilevamento di un DMG Tiley montato all'avvio da /Applicazioni (ad es. dopo copia manuale dal Finder) con offerta di espulsione e spostamento nel Cestino

## [1.1.7] - 2026-03-16

### Modificato

- Formato di distribuzione cambiato da zip a DMG con collegamento ad Applicazioni e layout Finder personalizzato (icone grandi, finestra quadrata)

### Correzioni

- Corretto "Sposta in Applicazioni" che falliva con errore di volume in sola lettura quando l'app veniva avviata da uno zip scaricato senza prima spostarla (Gatekeeper App Translocation)
- Mostra il dialogo "Copia in Applicazioni" invece di "Sposta" quando l'app viene avviata da un'immagine disco (DMG)

## [1.1.6] - 2026-03-16

### Correzioni

- Corretto il problema per cui la finestra delle impostazioni richiedeva due attivazioni per aprirsi su configurazioni multi-schermo (icona barra dei menu, Cmd+, e menu Tiley → Impostazioni tutti interessati)

## [1.1.5] - 2026-03-16

### Aggiunto

- Sovrapposizione multi-schermo: la finestra della griglia di layout appare ora simultaneamente su tutti gli schermi collegati
- Piastrellatura tra schermi: trascina la griglia o fai clic su un preset su uno schermo secondario per piastrellare la finestra di destinazione su quello schermo
- La sovrapposizione di anteprima appare sullo schermo dove viene visualizzata la finestra del preset

### Correzioni

- Corretto il layout massimizzato che non riempiva l'intero schermo durante la piastrellatura tra display di dimensioni diverse
- Corretto il problema per cui le scorciatoie da tastiera locali (tasti freccia, tasti di accesso rapido preset) non funzionavano dopo la seconda attivazione della sovrapposizione
- Corretto il problema per cui solo alcune finestre di sovrapposizione si chiudevano cliccando su una finestra di app in background; ora tutte le finestre si chiudono insieme
- Corretto l'evidenziazione hover/selezione preset che appariva su tutti gli schermi; ora appare solo sullo schermo dove si trova il cursore del mouse

## [1.1.4] - 2026-03-15

### Correzioni

- Corretto l'interruttore "Mostra icona Dock" che non funzionava: l'icona del Dock non appariva quando attivato, e la disattivazione faceva scomparire la finestra
- Impedito che l'app si chiudesse inaspettatamente alla chiusura di tutte le finestre
- Corretto il target della finestra che era Tiley stesso all'avvio tramite doppio clic; ora punta correttamente alla finestra dell'app precedentemente attiva
- Corretto il problema della finestra principale che appariva all'avvio come elemento di login: la finestra non si apre più all'avvio automatico del sistema

## [1.1.3] - 2026-03-15

### Correzioni

- Corretto il problema della sovrapposizione di anteprima della griglia che a volte rimaneva visibile sullo schermo, causando sovrapposizioni duplicate impilate

## [1.1.2] - 2026-03-15

### Aggiunto

- Localizzazione: spagnolo, tedesco, francese, portoghese (Brasile), russo, italiano

## [1.1.1] - 2026-03-15

## [1.1.0] - 2026-03-15

### Aggiunto

- Supporto modalità scura: tutti gli elementi dell'interfaccia si adattano automaticamente all'impostazione di aspetto del sistema

### Modificato

- La visualizzazione delle scorciatoie ora usa simboli (⌃ ⌥ ⇧ ⌘ ← → ↑ ↓) al posto dei nomi dei tasti in inglese

### Correzioni

- La finestra principale si nasconde automaticamente quando Sparkle mostra il dialogo di aggiornamento

## [1.0.1] - 2026-03-15

### Correzioni

- Aggiunta la localizzazione mancante per i tooltip dei pulsanti di aggiunta scorciatoia ("Aggiungi scorciatoia" / "Aggiungi scorciatoia globale")

## [1.0.0] - 2026-03-14

### Aggiunto

- Richiesta di spostare l'app in /Applicazioni quando avviata da un'altra posizione
- Flag globale per scorciatoia: ogni scorciatoia all'interno di un preset di layout può ora essere impostata individualmente come globale o locale
- Pulsanti di aggiunta separati per scorciatoie regolari e globali, con tooltip a comparsa istantanei

### Modificato

- Impostazione scorciatoia globale spostata dal livello preset al livello scorciatoia
- I preset esistenti con il vecchio flag globale a livello preset vengono migrati automaticamente

## [0.9.0] - 2026-03-14

- Rilascio iniziale

### Aggiunto

- Sovrapposizione a griglia per la piastrellatura delle finestre con dimensione griglia personalizzabile
- Scorciatoia da tastiera globale (Maiusc + Comando + Spazio) per attivare la sovrapposizione
- Trascinare sulle celle della griglia per definire l'area della finestra di destinazione
- Preset di layout per salvare e ripristinare le disposizioni delle finestre
- Supporto multi-display
- Opzione di avvio al login
- Localizzazione: inglese, giapponese, coreano, cinese semplificato, cinese tradizionale
