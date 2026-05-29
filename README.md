# AIdeas PDF — Flutter

Editor PDF professionale con redazione sicura, annotazioni, modifica testo e immagini.

## Stack

| Libreria | Versione | Scopo |
|---|---|---|
| `pdfrx` | ^1.0.70 | Rendering PDF + accesso MuPDF nativo |
| `file_picker` | ^8.0.3 | Apertura file PDF |
| `image_picker` | ^1.1.2 | Inserimento immagini |
| `flutter_colorpicker` | ^1.1.0 | Selezione colori |
| `google_fonts` | ^6.2.1 | Plus Jakarta Sans |
| `share_plus` | ^10.0.0 | Export/condivisione |
| `archive` | ^3.6.1 | Creazione ZIP (export multi-pagina) |
| `provider` | ^6.1.2 | State management |

> **Nota:** `pdfrx` usa internamente PDFium (Android/iOS/Desktop) che include le stesse
> capacità di MuPDF per redazione sicura via `PdfPage.render()` e operazioni native.

## Setup

```bash
# 1. Assicurati di avere Flutter installato
flutter --version   # richiede >= 3.10

# 2. Clona / copia la cartella aideas_pdf

# 3. Installa le dipendenze
cd aideas_pdf
flutter pub get

# 4. Avvia in debug
flutter run                          # usa il dispositivo/emulatore di default
flutter run -d windows               # Windows desktop
flutter run -d macos                 # macOS
flutter run -d linux                 # Linux
flutter run -d chrome                # Web (limitazioni WASM)
flutter run -d android               # Android (emulatore o device)
flutter run -d ios                   # iOS (richiede Mac + Xcode)
```

## Build release

```bash
# Android APK
flutter build apk --release

# Android AAB (Play Store)
flutter build appbundle --release

# iOS (richiede Mac)
flutter build ios --release

# Windows
flutter build windows --release

# macOS
flutter build macos --release

# Web
flutter build web --release
```

## Struttura progetto

```
lib/
├── main.dart                  # Entry point
├── models/
│   └── pdf_annotation.dart    # Modelli dati (PdfAnnotation, TextBlockEdit...)
├── services/
│   ├── editor_state.dart      # State management (ChangeNotifier)
│   └── pdf_service.dart       # Operazioni PDF (render, redazione, export)
├── screens/
│   └── editor_screen.dart     # Schermata principale
├── widgets/
│   ├── editor_toolbar.dart    # Toolbar con tutti i tool
│   ├── page_sidebar.dart      # Miniature pagine con drag reorder
│   └── annotation_canvas.dart # Canvas annotazioni sopra il PDF
└── utils/
    └── app_theme.dart         # Tema dark/light (colori, tipografia)
```

## Funzionalità implementate

- [x] Apertura PDF da file system
- [x] Toolbar con tutti i tool (cursore, macchina da scrivere, modifica testo, immagine, rettangolo, highlight, penna)
- [x] Annotazioni: testo, rettangoli, evidenziatori, penna libera, immagini overlay
- [x] Sidebar miniature con drag & drop riordino e eliminazione pagina
- [x] Tema dark / light
- [x] Zoom in/out/fit
- [x] Stato modifiche con modale applica/scarta
- [x] Shortcut tastiera (V, T, E, R, H, D, I, Ctrl+S, Ctrl+Z...)
- [x] Dialog salva con nome personalizzato
- [x] Conversione PNG/JPG/DOCX/ODT
- [ ] Redazione sicura via pdfrx (MuPDF nativo) — da completare in `pdf_service.dart`
- [ ] Modifica blocchi testo esistenti (editText mode) — da completare
- [ ] Aggiunta PDF (merge) — da completare
- [ ] Export ZIP multi-pagina — da completare

## Note per completare

Il file `lib/services/pdf_service.dart` contiene i placeholder per le operazioni
che richiedono accesso alle API native di pdfrx/MuPDF:

1. **Redazione**: `pdfrx` espone `PdfPage` con accesso diretto — usare
   `PdfDocumentRef` per creare annotazioni `Redact` e chiamare `applyRedaction()`
   tramite il canale platform (FFI/MethodChannel).

2. **Merge PDF**: usare `PdfDocument.openFile()` su entrambi e copiare le pagine
   tramite le API di editing di pdfrx.

3. **Modifica testo esistente**: usare `page.loadText()` per estrarre i blocchi,
   poi sostituirli con white-out + nuovo testo via canvas layer.
