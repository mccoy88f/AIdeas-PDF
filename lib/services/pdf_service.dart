import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as spdf;
import '../models/pdf_annotation.dart';
import 'editor_state.dart';

class PdfService {

  // ── Applica modifiche al PDF mantenendo il testo selezionabile ──
  //
  // Flusso:
  //   1. Carica il PDF con Syncfusion (engine nativo, puro Dart)
  //   2. Aggiunge PdfRedactionAnnotation per le aree da oscurare
  //   3. Chiama document.redact() → rimuove davvero testo/immagini dal content stream
  //   4. Disegna le annotazioni visive (typewriter, rect, highlight, draw, image)
  //      sul layer grafico delle pagine — il testo originale rimane selezionabile
  //   5. Salva come PDF vettoriale (non rasterizzato)
  static Future<File> applyChangesAndSave({
    required File sourceFile,
    required EditorState state,
    required String outputName,
  }) async {
    final dir = await getTemporaryDirectory();
    final outputPath = '${dir.path}/$outputName.pdf';

    final inputBytes = await sourceFile.readAsBytes();
    final document = spdf.PdfDocument(inputBytes: inputBytes);

    // Fase 1 — marca le aree di redazione
    for (int pageIdx = 0; pageIdx < document.pages.count; pageIdx++) {
      final page = document.pages[pageIdx];
      final pageNum = pageIdx + 1;
      _addRedactions(page, pageNum, state);
    }

    // Applica tutte le redazioni: rimuove il contenuto dal content stream
    document.redact();

    // Fase 2 — disegna le annotazioni visive sopra il contenuto esistente
    for (int pageIdx = 0; pageIdx < document.pages.count; pageIdx++) {
      final page = document.pages[pageIdx];
      final pageNum = pageIdx + 1;
      await _drawVisualAnnotations(page, pageNum, state);
    }

    final outputBytes = await document.save();
    document.dispose();
    await File(outputPath).writeAsBytes(outputBytes);
    return File(outputPath);
  }

  // ── Marca le aree da rimuovere come PdfRedactionAnnotation ──
  static void _addRedactions(
    spdf.PdfPage page,
    int pageNum,
    EditorState state,
  ) {
    final pageW = page.size.width;
    final pageH = page.size.height;

    // Tool redazione (X) → rettangolo nero, contenuto rimosso
    for (final ann in state.annotations) {
      if (ann.page != pageNum || ann.type != AnnotationType.redact) continue;
      page.annotations.add(spdf.PdfRedactionAnnotation(
        Rect.fromLTWH(ann.x * pageW, ann.y * pageH, ann.w * pageW, ann.h * pageH),
        fillColor: spdf.PdfColor(0, 0, 0),
      ));
    }

    // Blocchi di testo eliminati in editText mode → redazione bianca (invisibile)
    for (final edit in state.textEdits.values) {
      if (edit.page != pageNum || !edit.deleted) continue;
      // Le coordinate di origX/Y sono in punti PDF assoluti (da extractText)
      page.annotations.add(spdf.PdfRedactionAnnotation(
        Rect.fromLTWH(edit.origX, edit.origY, edit.origWidth, edit.origFontSize * 1.5),
        fillColor: spdf.PdfColor(255, 255, 255),
        borderColor: spdf.PdfColor(255, 255, 255),
      ));
    }

    // Immagini eliminate in editText mode → redazione bianca
    for (final edit in state.imageEdits.values) {
      if (edit.page != pageNum || !edit.deleted) continue;
      page.annotations.add(spdf.PdfRedactionAnnotation(
        Rect.fromLTWH(edit.origX, edit.origY, edit.origWidth, edit.origHeight),
        fillColor: spdf.PdfColor(255, 255, 255),
        borderColor: spdf.PdfColor(255, 255, 255),
      ));
    }
  }

  // ── Disegna le annotazioni visive sul layer grafico della pagina ──
  // Non tocca il content stream originale → il testo rimane selezionabile.
  static Future<void> _drawVisualAnnotations(
    spdf.PdfPage page,
    int pageNum,
    EditorState state,
  ) async {
    final pageW = page.size.width;
    final pageH = page.size.height;
    final graphics = page.graphics;

    for (final ann in state.annotations) {
      if (ann.page != pageNum || ann.type == AnnotationType.redact) continue;

      final c = ann.color;
      final color = spdf.PdfColor(c.red, c.green, c.blue);
      final x = ann.x * pageW;
      final y = ann.y * pageH;
      final w = ann.w * pageW;
      final h = ann.h * pageH;

      switch (ann.type) {
        case AnnotationType.text:
          if (ann.text == null) break;
          final font = spdf.PdfStandardFont(
            _mapFontFamily(ann.fontFamily),
            ann.fontSize,
          );
          graphics.drawString(
            ann.text!,
            font,
            brush: spdf.PdfSolidBrush(color),
            bounds: Rect.fromLTWH(x, y, pageW - x, pageH - y),
          );

        case AnnotationType.rect:
          graphics.drawRectangle(
            pen: spdf.PdfPen(color, width: ann.lineWidth),
            bounds: Rect.fromLTWH(x, y, w, h),
          );

        case AnnotationType.highlight:
          // Giallo semitrasparente (38% opacità ≈ 97/255)
          graphics.drawRectangle(
            brush: spdf.PdfSolidBrush(spdf.PdfColor(255, 215, 0, 97)),
            bounds: Rect.fromLTWH(x, y, w, h),
          );

        case AnnotationType.draw:
          if (ann.points == null || ann.points!.length < 2) break;
          final pen = spdf.PdfPen(color, width: ann.lineWidth);
          final points = ann.points!
            .map((p) => Offset(p.dx * pageW, p.dy * pageH))
            .toList();
          for (int i = 0; i < points.length - 1; i++) {
            graphics.drawLine(pen, points[i], points[i + 1]);
          }

        case AnnotationType.image:
          if (ann.imagePath == null) break;
          try {
            final imgBytes = await File(ann.imagePath!).readAsBytes();
            final pdfBitmap = spdf.PdfBitmap(imgBytes);
            graphics.drawImage(pdfBitmap, Rect.fromLTWH(x, y, w, h));
          } catch (_) {}

        case AnnotationType.redact:
          break; // già gestito in _addRedactions
      }
    }
  }

  static spdf.PdfFontFamily _mapFontFamily(String? family) {
    return switch (family?.toLowerCase()) {
      'times new roman' || 'times' => spdf.PdfFontFamily.timesRoman,
      'courier'                    => spdf.PdfFontFamily.courier,
      _                            => spdf.PdfFontFamily.helvetica,
    };
  }

  // ── Rasterizza una pagina come PNG (per miniature sidebar e export immagini) ──
  static Future<Uint8List> rasterizePage(
    PdfDocument doc,
    int pageIndex, {
    double scale = 2.5,
  }) async {
    final page = doc.pages[pageIndex];
    final width  = (page.width  * scale).toInt();
    final height = (page.height * scale).toInt();

    final pdfImage = await page.render(
      fullWidth:  width.toDouble(),
      fullHeight: height.toDouble(),
    );
    final uiImage = await _pdfImageToUiImage(pdfImage, width, height);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    canvas.drawImage(uiImage, Offset.zero, Paint());
    final picture = recorder.endRecording();
    final img = await picture.toImage(width, height);
    final pngData = await img.toByteData(format: ui.ImageByteFormat.png);
    return pngData!.buffer.asUint8List();
  }

  static Future<ui.Image> _pdfImageToUiImage(
    PdfImage? pdfImage,
    int width,
    int height,
  ) async {
    if (pdfImage == null) {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.white, BlendMode.src);
      return recorder.endRecording().toImage(width, height);
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pdfImage.pixels,
      pdfImage.width,
      pdfImage.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  // ── Converti pagine in immagini PNG/JPG ──
  static Future<List<Uint8List>> pagesToImages(
    PdfDocument doc,
    List<int> pageNums, {
    double scale = 2.0,
    bool jpeg = false,
  }) async {
    final results = <Uint8List>[];
    for (final n in pageNums) {
      final idx = n - 1;
      if (idx < 0 || idx >= doc.pages.length) continue;
      results.add(await rasterizePage(doc, idx, scale: scale));
    }
    return results;
  }

  // ── Estrai testo strutturato da una pagina (per editText mode) ──
  static Future<List<PdfTextItem>> extractText(
    PdfDocument doc,
    int pageIndex,
  ) async {
    final page = doc.pages[pageIndex];
    final textPage = await page.loadText();
    final items = <PdfTextItem>[];
    if (textPage == null) return items;
    int idx = 0;
    for (final frag in textPage.fragments) {
      items.add(PdfTextItem(
        index: idx++,
        text: frag.text,
        x: frag.bounds.left,
        y: frag.bounds.top,
        width: frag.bounds.width,
        height: frag.bounds.height,
        fontSize: frag.bounds.height * 0.85,
      ));
    }
    return items;
  }
}
