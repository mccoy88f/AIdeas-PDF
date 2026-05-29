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

  // ── Applica modifiche — approccio ibrido ──────────────────────────────────
  //
  // Pagine SENZA redazione/eliminazioni:
  //   → Syncfusion disegna le annotazioni sul layer grafico della pagina
  //   → il testo originale rimane selezionabile nel PDF salvato
  //
  // Pagine CON redazione o blocchi eliminati:
  //   → la pagina viene rasterizzata con pdfrx (dart:ui Canvas)
  //   → il contenuto oscurato/eliminato è irrecuperabile
  //   → il testo su quella pagina non è più selezionabile (trade-off accettato)
  //
  // Limitazione tecnica: nessun package Dart puro espone API per rimuovere
  // oggetti dal content stream PDF. La rasterizzazione è l'unica garanzia
  // di rimozione vera del contenuto su piattaforme cross-platform.
  static Future<File> applyChangesAndSave({
    required File sourceFile,
    required EditorState state,
    required String outputName,
  }) async {
    final dir = await getTemporaryDirectory();
    final outputPath = '${dir.path}/$outputName.pdf';

    final inputBytes = await sourceFile.readAsBytes();
    final document  = spdf.PdfDocument(inputBytes: inputBytes);

    // pdfrx usato solo per le pagine che richiedono rasterizzazione
    PdfDocument? pdfrxDoc;
    if (_hasRedactedPages(state)) {
      pdfrxDoc = await PdfDocument.openFile(sourceFile.path);
    }

    for (int pageIdx = 0; pageIdx < document.pages.count; pageIdx++) {
      final page    = document.pages[pageIdx];
      final pageNum = pageIdx + 1;

      if (_pageNeedsRaster(pageNum, state)) {
        // ── Pagina rasterizzata: contenuto rimosso definitivamente ──
        final rasterBytes = await _renderPageWithAnnotations(
          pdfrxDoc!, pageIdx, state.annotations,
        );
        final bitmap = spdf.PdfBitmap(rasterBytes);
        page.graphics.drawImage(
          bitmap,
          Rect.fromLTWH(0, 0, page.size.width, page.size.height),
        );
      } else {
        // ── Pagina vettoriale: annotazioni visive, testo selezionabile ──
        await _drawVisualAnnotations(page, pageNum, state);
      }
    }

    pdfrxDoc?.dispose();
    final outputBytes = await document.save();
    document.dispose();
    await File(outputPath).writeAsBytes(outputBytes);
    return File(outputPath);
  }

  // Restituisce true se la pagina contiene redazioni o elementi eliminati
  static bool _pageNeedsRaster(int pageNum, EditorState state) {
    if (state.annotations.any(
      (a) => a.page == pageNum && a.type == AnnotationType.redact,
    )) return true;
    if (state.textEdits.values.any(
      (e) => e.page == pageNum && e.deleted,
    )) return true;
    if (state.imageEdits.values.any(
      (e) => e.page == pageNum && e.deleted,
    )) return true;
    return false;
  }

  static bool _hasRedactedPages(EditorState state) {
    return state.annotations.any((a) => a.type == AnnotationType.redact) ||
           state.textEdits.values.any((e) => e.deleted) ||
           state.imageEdits.values.any((e) => e.deleted);
  }

  // ── Disegna annotazioni visive sul layer grafico Syncfusion ──
  // Aggiunge contenuto SOPRA la pagina esistente senza toccare il content stream.
  static Future<void> _drawVisualAnnotations(
    spdf.PdfPage page,
    int pageNum,
    EditorState state,
  ) async {
    final pageW    = page.size.width;
    final pageH    = page.size.height;
    final graphics = page.graphics;

    for (final ann in state.annotations) {
      if (ann.page != pageNum || ann.type == AnnotationType.redact) continue;

      final c     = ann.color;
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
          // giallo semitrasparente (38% ≈ 97/255)
          graphics.drawRectangle(
            brush: spdf.PdfSolidBrush(spdf.PdfColor(255, 215, 0, 97)),
            bounds: Rect.fromLTWH(x, y, w, h),
          );

        case AnnotationType.draw:
          if (ann.points == null || ann.points!.length < 2) break;
          final pen    = spdf.PdfPen(color, width: ann.lineWidth);
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
            graphics.drawImage(
              spdf.PdfBitmap(imgBytes),
              Rect.fromLTWH(x, y, w, h),
            );
          } catch (_) {}

        case AnnotationType.redact:
          break;
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

  // ── Rasterizza una pagina con annotazioni baked tramite dart:ui Canvas ──
  static Future<Uint8List> _renderPageWithAnnotations(
    PdfDocument doc,
    int pageIndex,
    List<PdfAnnotation> annotations, {
    double scale = 2.5,
  }) async {
    final page   = doc.pages[pageIndex];
    final width  = (page.width  * scale).toInt();
    final height = (page.height * scale).toInt();
    final sz     = Size(width.toDouble(), height.toDouble());

    final pdfImage = await page.render(
      fullWidth:  width.toDouble(),
      fullHeight: height.toDouble(),
    );
    final uiImage = await _pdfImageToUiImage(pdfImage, width, height);

    final recorder = ui.PictureRecorder();
    final canvas   = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    canvas.drawImage(uiImage, Offset.zero, Paint());

    for (final ann in annotations) {
      if (ann.page != pageIndex + 1) continue;
      await _drawAnnotationOnCanvas(canvas, sz, ann, scale);
    }

    final picture = recorder.endRecording();
    final img     = await picture.toImage(width, height);
    final pngData = await img.toByteData(format: ui.ImageByteFormat.png);
    return pngData!.buffer.asUint8List();
  }

  static Future<void> _drawAnnotationOnCanvas(
    Canvas canvas,
    Size sz,
    PdfAnnotation ann,
    double scale,
  ) async {
    switch (ann.type) {
      case AnnotationType.redact:
        canvas.drawRect(
          Rect.fromLTWH(ann.x * sz.width, ann.y * sz.height, ann.w * sz.width, ann.h * sz.height),
          Paint()..color = Colors.black..style = PaintingStyle.fill,
        );

      case AnnotationType.rect:
        canvas.drawRect(
          Rect.fromLTWH(ann.x * sz.width, ann.y * sz.height, ann.w * sz.width, ann.h * sz.height),
          Paint()
            ..color = ann.color
            ..strokeWidth = ann.lineWidth * scale / 2
            ..style = PaintingStyle.stroke,
        );

      case AnnotationType.highlight:
        canvas.drawRect(
          Rect.fromLTWH(ann.x * sz.width, ann.y * sz.height, ann.w * sz.width, ann.h * sz.height),
          Paint()
            ..color = const Color(0xFFFFD700).withOpacity(0.45)
            ..style = PaintingStyle.fill,
        );

      case AnnotationType.draw:
        if (ann.points == null || ann.points!.length < 2) return;
        final path = Path()
          ..moveTo(ann.points![0].dx * sz.width, ann.points![0].dy * sz.height);
        for (int i = 1; i < ann.points!.length; i++) {
          path.lineTo(ann.points![i].dx * sz.width, ann.points![i].dy * sz.height);
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = ann.color
            ..strokeWidth = ann.lineWidth * scale / 2
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );

      case AnnotationType.text:
        if (ann.text == null) return;
        final fontSize = ann.fontSize * scale;
        final para = (ui.ParagraphBuilder(ui.ParagraphStyle(
          fontSize: fontSize, fontFamily: ann.fontFamily,
        ))
          ..pushStyle(ui.TextStyle(
            color: ann.color, fontSize: fontSize, fontFamily: ann.fontFamily,
          ))
          ..addText(ann.text!))
          .build()
          ..layout(ui.ParagraphConstraints(width: sz.width - ann.x * sz.width));
        canvas.drawParagraph(para, Offset(ann.x * sz.width, ann.y * sz.height));

      case AnnotationType.image:
        if (ann.imagePath == null) return;
        try {
          final bytes = await File(ann.imagePath!).readAsBytes();
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          paintImage(
            canvas: canvas,
            rect: Rect.fromLTWH(
              ann.x * sz.width, ann.y * sz.height, ann.w * sz.width, ann.h * sz.height,
            ),
            image: frame.image,
            fit: BoxFit.fill,
          );
        } catch (_) {}
    }
  }

  // ── Rasterizza una pagina senza annotazioni (per miniature e export) ──
  static Future<Uint8List> rasterizePage(
    PdfDocument doc,
    int pageIndex, {
    double scale = 2.5,
  }) async {
    final page   = doc.pages[pageIndex];
    final width  = (page.width  * scale).toInt();
    final height = (page.height * scale).toInt();

    final pdfImage = await page.render(
      fullWidth:  width.toDouble(),
      fullHeight: height.toDouble(),
    );
    final uiImage = await _pdfImageToUiImage(pdfImage, width, height);

    final recorder = ui.PictureRecorder();
    final canvas   = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    canvas.drawImage(uiImage, Offset.zero, Paint());
    final picture  = recorder.endRecording();
    final img      = await picture.toImage(width, height);
    final pngData  = await img.toByteData(format: ui.ImageByteFormat.png);
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
      pdfImage.pixels, pdfImage.width, pdfImage.height,
      ui.PixelFormat.rgba8888, completer.complete,
    );
    return completer.future;
  }

  // ── Converti pagine in PNG/JPG ──
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

  // ── Estrai testo strutturato (per editText mode) ──
  static Future<List<PdfTextItem>> extractText(
    PdfDocument doc,
    int pageIndex,
  ) async {
    final page     = doc.pages[pageIndex];
    final textPage = await page.loadText();
    final items    = <PdfTextItem>[];
    if (textPage == null) return items;
    int idx = 0;
    for (final frag in textPage.fragments) {
      items.add(PdfTextItem(
        index: idx++,
        text: frag.text,
        x: frag.bounds.left,  y: frag.bounds.top,
        width: frag.bounds.width, height: frag.bounds.height,
        fontSize: frag.bounds.height * 0.85,
      ));
    }
    return items;
  }
}
