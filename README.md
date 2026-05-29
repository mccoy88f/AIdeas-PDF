# AIdeas PDF — Flutter

Editor PDF professionale con redazione sicura, annotazioni, modifica testo e immagini.

[![Build Windows](https://github.com/mccoy88f/AIdeas-PDF/actions/workflows/build-windows.yml/badge.svg)](https://github.com/mccoy88f/AIdeas-PDF/actions/workflows/build-windows.yml)
[![Deploy Web](https://github.com/mccoy88f/AIdeas-PDF/actions/workflows/deploy-web.yml/badge.svg)](https://github.com/mccoy88f/AIdeas-PDF/actions/workflows/deploy-web.yml)

## Demo

**Web app:** [mccoy88f.github.io/AIdeas-PDF](https://mccoy88f.github.io/AIdeas-PDF/)

**Windows:** scarica lo zip dalla tab [Actions → Build Windows → Artifacts](https://github.com/mccoy88f/AIdeas-PDF/actions/workflows/build-windows.yml)

---

## Funzionalità

| Feature | Shortcut | Stato |
|---|---|---|
| Apertura PDF | Ctrl+O | ✅ |
| Cursore / selezione | V | ✅ |
| Macchina da scrivere | T | ✅ |
| Modifica testo esistente | E | ✅ |
| Inserisci immagine | I | ✅ |
| Rettangolo | R | ✅ |
| Evidenziatore | H | ✅ |
| Penna libera | D | ✅ |
| **Redazione sicura** | **X** | ✅ |
| Salva / applica modifiche | Ctrl+S | ✅ |
| Undo | Ctrl+Z | ✅ |
| Zoom in/out | + / - | ✅ |
| Sidebar miniature + drag & drop | — | ✅ |
| Tema dark / light | — | ✅ |
| Conversione PNG/JPG/DOCX/ODT | — | ✅ |
| Export ZIP multi-pagina | — | 🔜 |
| Merge PDF | — | 🔜 |

### Redazione sicura

Il tool **Redazione** (tasto `X`) oscura permanentemente il contenuto selezionato.
Quando salvi con "Applica e aggiorna", ogni pagina viene rasterizzata e il testo
sottostante ai blocchi neri è **irrecuperabile**: il PDF in output è image-based,
senza testo estraibile.

---

## Stack

| Libreria | Versione | Scopo |
|---|---|---|
| `pdfrx` | ^1.0.70 | Rendering PDF (PDFium/MuPDF nativo) |
| `pdf` | ^3.11.0 | Generazione PDF con annotazioni baked |
| `provider` | ^6.1.2 | State management |
| `file_picker` | ^8.0.3 | Apertura file PDF |
| `image_picker` | ^1.1.2 | Inserimento immagini |
| `share_plus` | ^10.0.0 | Export / condivisione |
| `flutter_colorpicker` | ^1.1.0 | Selezione colori |
| `archive` | ^3.6.1 | Export ZIP multi-pagina (in sviluppo) |
| `docx_template` | ^0.4.0 | Export DOCX/ODT |

---

## Struttura progetto

```
lib/
├── main.dart                  # Entry point + Provider setup
├── models/
│   └── pdf_annotation.dart    # PdfAnnotation, TextBlockEdit, ImageBlockEdit
├── services/
│   ├── editor_state.dart      # ChangeNotifier — stato globale editor
│   └── pdf_service.dart       # Rasterizzazione, bake annotazioni, export PDF
├── screens/
│   └── editor_screen.dart     # Schermata principale + shortcut tastiera
├── widgets/
│   ├── editor_toolbar.dart    # Toolbar con palette tool e controlli
│   ├── page_sidebar.dart      # Miniature pagine con drag & drop
│   └── annotation_canvas.dart # Canvas disegno annotazioni sopra il PDF
└── utils/
    └── app_theme.dart         # Tema dark/light
```

---

## Setup locale

```bash
# Requisiti: Flutter >= 3.10
flutter --version

git clone https://github.com/mccoy88f/AIdeas-PDF.git
cd AIdeas-PDF

# Prima volta: aggiunge il supporto per la piattaforma target
flutter create --platforms=windows .   # oppure web, linux, macos, android, ios

flutter pub get
flutter run -d windows    # o chrome, linux, macos, android, ios
```

## Build release

```bash
# Windows
flutter create --platforms=windows .
flutter build windows --release
# Output: build/windows/x64/runner/Release/

# Web
flutter create --platforms=web .
flutter build web --release --base-href "/AIdeas-PDF/"
# Output: build/web/

# Android APK
flutter build apk --release

# macOS
flutter build macos --release
```

---

## CI / CD

| Workflow | Trigger | Output |
|---|---|---|
| **Build Windows** | Push su qualsiasi branch + manuale | ZIP scaricabile dagli Artifacts (30 gg) |
| **Deploy Web** | Push su `main` + manuale | Deploy su GitHub Pages |

Per abilitare GitHub Pages: **Settings → Pages → Source → GitHub Actions**
