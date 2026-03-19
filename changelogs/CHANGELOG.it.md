# Registro delle modifiche

## [Unreleased]

## [2.0.1] - 2026-03-19

### Modificato

- Pannello impostazioni ridisegnato in stile Tahoe: sezioni con sfondo in vetro (Liquid Glass su macOS 26+), barra degli strumenti compatta con pulsanti indietro/esci e righe raggruppate in stile iOS con controlli in linea

### Corretto

- Corretto un problema in cui il posizionamento della finestra utilizzava la geometria dello schermo obsoleta quando il Dock o la barra dei menu si mostravano/nascondevano automaticamente mentre l'overlay era aperto
- Corretto un problema in cui la finestra non si spostava nella posizione selezionata quando l'app di destinazione riposiziona la finestra durante il ridimensionamento; l'ultima operazione AX è ora sempre un'impostazione di posizione

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
