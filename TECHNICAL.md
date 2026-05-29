# AIdeas PDF — Technical Reference

Documentazione tecnica per sviluppatori.

---

## Stack

| Libreria | Versione | Scopo |
|---|---|---|
| `pdfrx` | ^1.0.70 | Rendering PDF (PDFium/MuPDF nativo bundled) |
| `pdf` | ^3.11.0 | Generazione PDF con annotazioni baked |
| `provider` | ^6.1.2 | State management (ChangeNotifier) |
| `file_picker` | ^8.0.3 | Apertura file dal filesystem |
| `image_picker` | ^1.1.2 | Inserimento immagini dalla galleria |
| `share_plus` | ^10.0.0 | Export e condivisione su mobile |
| `flutter_colorpicker` | ^1.1.0 | Color picker UI |
| `archive` | ^3.6.1 | Export ZIP multi-pagina (in sviluppo) |
| `docx_template` | ^0.4.0 | Export DOCX/ODT |

> `pdfrx` include PDFium precompilato per Android, iOS e Desktop. Su web usa una build WASM dello stesso engine.

---

## Architettura

```
lib/
├── main.dart                  # Entry point — ChangeNotifierProvider root
├── models/
│   └── pdf_annotation.dart    # Modelli dati puri (no Flutter dipendencies)
├── services/
│   ├── editor_state.dart      # ChangeNotifier — unica fonte di verità
│   └── pdf_service.dart       # I/O PDF: rasterizzazione, bake, export
├── screens/
│   └── editor_screen.dart     # Schermata principale + keyboard handler
├── widgets/
│   ├── editor_toolbar.dart    # Toolbar stateless con Consumer
│   ├── page_sidebar.dart      # Miniature pagine con drag & drop
│   └── annotation_canvas.dart # GestureDetector + CustomPainter
└── utils/
    └── app_theme.dart         # ThemeData dark/light, costanti colori
```

### Flusso dati

```
GestureDetector (annotation_canvas)
    │  tap / pan events
    ▼
EditorState.addAnnotation()      ← ChangeNotifier
    │  notifyListeners()
    ▼
AnnotationCanvas rebuild         → CustomPainter._drawAnn()
EditorToolbar rebuild            → tool attivo, colori
PageSidebar rebuild              → miniature aggiornate
```

---

## Modelli dati

### `PdfAnnotation`
Rappresenta una singola annotazione sovrapposta al PDF.

```dart
class PdfAnnotation {
  final String id;   // microsecondsSinceEpoch
  int page;          // 1-based
  AnnotationType type;
  double x, y, w, h; // normalizzati 0.0–1.0 rispetto alle dimensioni della pagina
  Color color;
  double lineWidth;
  double fontSize;
  String? fontFamily;
  String? text;
  List<Offset>? points;   // per AnnotationType.draw
  String? imagePath;      // path locale per AnnotationType.image
  List<Rect>? highlightRects;
}

enum AnnotationType { text, rect, highlight, draw, image, redact }
enum EditorTool     { select, typewriter, editText, rect, highlight, draw, image, redact }
```

Le coordinate sono **normalizzate** (0.0–1.0) rispetto alle dimensioni della pagina PDF, indipendentemente dallo zoom. La conversione avviene nel painter e nel service al momento del rendering.

### `TextBlockEdit` / `ImageBlockEdit`
Modifiche a blocchi di testo o immagini già presenti nel PDF originale (feature editText, in sviluppo).

---

## EditorState

Unico `ChangeNotifier` dell'app, consumato da tutti i widget tramite `context.watch<EditorState>()`.

Sezioni principali:

| Gruppo | Campi chiave |
|---|---|
| File | `pdfFile`, `fileName`, `numPages`, `currentPage` |
| Vista | `zoom`, `isDark`, `sidebarVisible` |
| Tool | `tool`, `color`, `lineWidth`, `fontSize`, `fontFamily` |
| Annotazioni | `annotations`, `selectedId`, `pendingIds` |
| Modifiche | `textEdits`, `imageEdits`, `hasChanges` |

**Undo** è implementato come rimozione dell'ultima annotazione della pagina corrente (`undoLast()`). Non c'è uno stack undo completo.

---

## PdfService

Tutte le operazioni di I/O sono metodi `static` su `PdfService`.

### `applyChangesAndSave()`
Processo di bake delle annotazioni nel PDF:

1. Apre il documento originale con `pdfrx`
2. Per ogni pagina chiama `_renderPageWithAnnotations()`
3. `_renderPageWithAnnotations()` rasterizza la pagina via `PdfPage.render()` → `decodeImageFromPixels()` → `ui.Image`
4. Disegna le annotazioni sopra con `dart:ui Canvas` (`_drawAnnotation()`)
5. Esporta ogni pagina come PNG (`ui.ImageByteFormat.png`)
6. Assembla tutte le pagine in un nuovo PDF con il package `pdf` (`pw.Document`)
7. Salva in `getTemporaryDirectory()`

Il PDF risultante è **image-based**: nessun testo estraibile, redazioni irrecuperabili.

### `_pdfImageToUiImage()`
Converte `PdfImage?` (pdfrx 1.0.103+) in `ui.Image` tramite `ui.decodeImageFromPixels()` usando il buffer `PdfImage.pixels` (RGBA8888). Se `PdfImage` è null restituisce una pagina bianca vuota.

### `rasterizePage()` / `pagesToImages()`
Rasterizzazione senza annotazioni, usata per l'export PNG/JPG.

### `extractText()`
Estrae frammenti di testo strutturati da una pagina tramite `PdfPage.loadText()`. Usato dal tool editText (in sviluppo).

---

## Coordinate e zoom

Le annotazioni sono salvate con coordinate normalizzate `[0, 1]`. La conversione avviene in due punti:

**Canvas (display):**
```dart
Offset _toNorm(Offset pos) => Offset(
  pos.dx / (pageSize.width * zoom),
  pos.dy / (pageSize.height * zoom),
);
```

**Export (pdf_service):**
```dart
// x, y, w, h normalizzati → pixel nell'immagine rasterizzata
Rect.fromLTWH(ann.x * sz.width, ann.y * sz.height, ann.w * sz.width, ann.h * sz.height)
```

---

## CI/CD

| Workflow | File | Trigger | Runner |
|---|---|---|---|
| Build Windows | `.github/workflows/build-windows.yml` | push su tutti i branch + manuale | `windows-latest` |
| Deploy Web | `.github/workflows/deploy-web.yml` | push su `main` + manuale | `ubuntu-latest` |

Entrambi i workflow eseguono `flutter create --platforms=<target> .` prima del build per generare i file di scaffolding della piattaforma (non inclusi nel repo).

L'output Windows è uno ZIP scaricabile dagli Artifacts per 30 giorni.
Il deploy web pubblica su GitHub Pages con `--base-href "/AIdeas-PDF/"`.

---

## Setup locale

```bash
git clone https://github.com/mccoy88f/AIdeas-PDF.git
cd AIdeas-PDF

# Aggiunge i file di scaffolding per la piattaforma target (una volta sola)
flutter create --platforms=windows .   # oppure web, linux, macos, android, ios

flutter pub get
flutter run -d windows    # o chrome, linux, macos, android, ios
```

### Build release

```bash
# Windows
flutter create --platforms=windows .
flutter build windows --release
# → build/windows/x64/runner/Release/

# Web
flutter create --platforms=web .
flutter build web --release --base-href "/AIdeas-PDF/"
# → build/web/

# Android
flutter build apk --release
```

---

## Funzionalità in sviluppo

| Feature | Note |
|---|---|
| Export ZIP multi-pagina | Dipendenza `archive` già presente, logica da collegare al dialog conversione |
| Merge PDF | Aprire due `PdfDocument`, copiare le pagine nel nuovo `pw.Document` |
| Modifica testo esistente | `extractText()` già implementato; manca l'UI di selezione e sostituzione nel canvas |
