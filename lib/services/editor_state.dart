import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/pdf_annotation.dart';

class EditorState extends ChangeNotifier {
  // ── File ──
  File? pdfFile;
  Uint8List? pdfBytes; // populated on web (dart:io File not usable)
  String fileName = 'documento';
  int numPages = 0;
  int currentPage = 1;

  // ── Vista ──
  double zoom = 1.0;
  bool sidebarVisible = true;
  bool isDark = true;

  // ── Tool ──
  EditorTool tool = EditorTool.select;
  Color color = const Color(0xFF1d1d1b);
  double lineWidth = 2.0;
  double fontSize = 14.0;
  String fontFamily = 'Helvetica';

  // ── Annotazioni aggiunte ──
  final List<PdfAnnotation> annotations = [];
  String? selectedId;

  // ── Modifiche a testo/immagini esistenti ──
  final Map<String, TextBlockEdit> textEdits = {};
  final Map<String, ImageBlockEdit> imageEdits = {};

  // ── Pending (non ancora baked nel PDF) ──
  final Set<String> pendingIds = {};

  // ────────────────────────────────────────
  // FILE
  // ────────────────────────────────────────
  void loadFile(File file, {String? fileName, Uint8List? bytes}) {
    pdfFile = file;
    pdfBytes = bytes;
    this.fileName = fileName ?? file.path.split(Platform.pathSeparator).last.replaceAll('.pdf', '');
    currentPage = 1;
    zoom = 1.0;
    annotations.clear();
    textEdits.clear();
    imageEdits.clear();
    pendingIds.clear();
    selectedId = null;
    notifyListeners();
  }

  // ────────────────────────────────────────
  // NAVIGAZIONE
  // ────────────────────────────────────────
  void goToPage(int page) {
    if (page < 1 || page > numPages) return;
    currentPage = page;
    selectedId = null;
    notifyListeners();
  }

  void setNumPages(int n) { numPages = n; notifyListeners(); }

  // ────────────────────────────────────────
  // ZOOM
  // ────────────────────────────────────────
  void zoomIn()  { zoom = (zoom * 1.25).clamp(0.2, 4.0); notifyListeners(); }
  void zoomOut() { zoom = (zoom / 1.25).clamp(0.2, 4.0); notifyListeners(); }
  void setZoom(double v) { zoom = v.clamp(0.2, 4.0); notifyListeners(); }

  // ────────────────────────────────────────
  // UI
  // ────────────────────────────────────────
  void toggleSidebar() { sidebarVisible = !sidebarVisible; notifyListeners(); }
  void toggleTheme()   { isDark = !isDark; notifyListeners(); }

  void setTool(EditorTool t) {
    tool = t;
    selectedId = null;
    notifyListeners();
  }

  void setColor(Color c)       { color = c; notifyListeners(); }
  void setLineWidth(double v)  { lineWidth = v; notifyListeners(); }
  void setFontSize(double v)   { fontSize = v; notifyListeners(); }
  void setFontFamily(String f) { fontFamily = f; notifyListeners(); }

  // ────────────────────────────────────────
  // ANNOTAZIONI
  // ────────────────────────────────────────
  void addAnnotation(PdfAnnotation ann) {
    annotations.add(ann);
    pendingIds.add(ann.id);
    selectedId = ann.id;
    notifyListeners();
  }

  void updateAnnotation(String id, {double? x, double? y, double? w, double? h, String? text}) {
    final ann = annotations.firstWhere((a) => a.id == id);
    if (x != null) ann.x = x;
    if (y != null) ann.y = y;
    if (w != null) ann.w = w;
    if (h != null) ann.h = h;
    if (text != null) ann.text = text;
    notifyListeners();
  }

  void deleteSelected() {
    if (selectedId == null) return;
    annotations.removeWhere((a) => a.id == selectedId);
    pendingIds.remove(selectedId);
    selectedId = null;
    notifyListeners();
  }

  void selectAnnotation(String? id) {
    selectedId = id;
    notifyListeners();
  }

  void undoLast() {
    final pageAnns = annotations.where((a) => a.page == currentPage).toList();
    if (pageAnns.isEmpty) return;
    final last = pageAnns.last;
    annotations.remove(last);
    pendingIds.remove(last.id);
    if (selectedId == last.id) selectedId = null;
    notifyListeners();
  }

  // ────────────────────────────────────────
  // TEXT / IMAGE BLOCK EDITS
  // ────────────────────────────────────────
  void editTextBlock(String key, TextBlockEdit edit) {
    textEdits[key] = edit;
    notifyListeners();
  }

  void deleteTextBlock(String key) {
    textEdits[key]?.deleted = true;
    notifyListeners();
  }

  void editImageBlock(String key, ImageBlockEdit edit) {
    imageEdits[key] = edit;
    notifyListeners();
  }

  void deleteImageBlock(String key) {
    imageEdits[key]?.deleted = true;
    notifyListeners();
  }

  // ────────────────────────────────────────
  // STATO MODIFICHE
  // ────────────────────────────────────────
  bool get hasChanges =>
    pendingIds.isNotEmpty ||
    textEdits.isNotEmpty ||
    imageEdits.isNotEmpty;

  void clearEdits() {
    textEdits.clear();
    imageEdits.clear();
    pendingIds.clear();
    notifyListeners();
  }

  void discardChanges() {
    annotations.removeWhere((a) => pendingIds.contains(a.id));
    textEdits.clear();
    imageEdits.clear();
    pendingIds.clear();
    selectedId = null;
    notifyListeners();
  }

  // ────────────────────────────────────────
  // PAGINE (per riordino e eliminazione)
  // ────────────────────────────────────────
  void remapAnnotationsAfterDelete(int deletedPage) {
    annotations.removeWhere((a) => a.page == deletedPage);
    for (final a in annotations) {
      if (a.page > deletedPage) a.page--;
    }
    final newTextEdits = <String, TextBlockEdit>{};
    for (final e in textEdits.entries) {
      if (e.value.page == deletedPage) continue;
      final newPage = e.value.page > deletedPage ? e.value.page - 1 : e.value.page;
      e.value.page = newPage;
      newTextEdits[e.key] = e.value;
    }
    textEdits
      ..clear()
      ..addAll(newTextEdits);
    notifyListeners();
  }
}
