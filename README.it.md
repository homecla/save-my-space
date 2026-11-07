# Save My Space

[English](README.md) · **Italiano**

Analizza la tua home su macOS e suggerisce cosa pulire. Si usa da riga di comando (`smspace`)
o con un'interfaccia grafica SwiftUI opzionale. Disponibile in italiano e in inglese.

**Sicuro per impostazione predefinita:** `scan` non modifica nulla; `clean` sposta gli elementi
nel **Cestino** (mai cancellazione definitiva), solo dopo una conferma esplicita, e ogni pulizia
viene registrata in uno storico che permette di ripristinarla con `restore`.

## Cosa cerca

| Categoria | Esempi | Rischio |
|---|---|---|
| Cache | `~/Library/Caches/*`, Homebrew, pip | sicuro |
| Log | `~/Library/Logs` | sicuro |
| Sviluppo | DerivedData, DeviceSupport, cache npm/Gradle, `node_modules`/`.venv`/`target`/`build` di progetti fermi | sicuro / da verificare |
| Download vecchi | installer `.dmg`/`.pkg`, file non usati da più di 90 giorni | da verificare |
| File grandi | file oltre 500 MB nelle tue cartelle | da verificare |
| Duplicati | file con contenuto identico (SHA-256) | da verificare |
| Dati delle app | cartelle grandi in Application Support, Games, `~/.qualcosa` | attenzione |
| Backup iOS, Mail, Messaggi, Docker, Cestino | | solo segnalati o attenzione |

iCloud Drive, CloudStorage e la Libreria Foto non vengono mai analizzati.

## Uso

```sh
smspace                          # = scan
smspace scan --limit 50
smspace scan --category caches,developer --risk safe
smspace scan --json > report.json
smspace scan -o report.md        # salva il report (.md, .csv, .json)
smspace scan --large-size 1G --older-than 180d --no-duplicates

smspace clean --dry-run          # cosa verrebbe spostato (solo rischio "sicuro")
smspace clean                    # chiede conferma, poi sposta nel Cestino
smspace clean --risk review -i   # conferma elemento per elemento
smspace clean --yes              # senza conferma: consentito solo per il rischio "sicuro"

smspace history                  # storico delle pulizie (numerate: #1 = la più recente)
smspace history -d               # con i singoli elementi e dove sono nel Cestino
smspace restore                  # ripristina l'ultima pulizia
smspace restore --entry 2 --path ~/Library/Caches/pip   # solo un elemento di una pulizia precedente

smspace gui                      # apre l'interfaccia grafica
```

## Lingua

La lingua si sceglie in quest'ordine: opzione `--lang en|it`, variabile d'ambiente
`SMSPACE_LANG`, lingua di sistema; se nessuna è supportata si usa l'inglese.

```sh
smspace --lang it scan
SMSPACE_LANG=en smspace history
```

Nell'app la lingua si cambia da *Impostazioni* (Automatica / English / Italiano).

## Report, storico e ripristino

- `scan -o report.md` (o `.csv`, `.json`) salva i suggerimenti mostrati, con gli stessi filtri.
- `clean --dry-run --report proposta.md` salva cosa *verrebbe* spostato.
- Ogni `clean`, da CLI o da GUI, viene registrato in
  `~/Library/Application Support/save-my-space/history.jsonl`: percorso originale, dimensione,
  categoria e **posizione nel Cestino**. `clean --report pulizia.md` salva anche il resoconto
  della singola pulizia; `history -o storico.csv` esporta lo storico.
- `restore` rimette gli elementi nella posizione originale finché sono nel Cestino.
  Non sovrascrive mai nulla: se la posizione è occupata l'elemento resta nel Cestino.
- Nella GUI: menu *Report* › *Esporta report…* / *Mostra storico delle pulizie* /
  *Ripristina ultima pulizia…*.

Per un'analisi completa concedi l'*Accesso completo al disco* al Terminale
(Impostazioni di Sistema › Privacy e sicurezza).

## Compilazione

Richiede macOS 14+ e Swift 6.

```sh
swift build                  # CLI + app di debug
swift run smspace
swift run SaveMySpaceApp
make app                     # crea dist/Save My Space.app
make install                 # CLI `smspace` in ~/.local/bin, app in ~/Applications
make test                    # test (richiede Xcode)
```

## Struttura

- `Sources/SaveMySpaceCore` — scansione, regole, report, Cestino, ripristino, localizzazione
- `Sources/smspace` — CLI (swift-argument-parser)
- `Sources/SaveMySpaceApp` — interfaccia SwiftUI
- `Tests/SaveMySpaceCoreTests` — test su home fittizie in cartelle temporanee
