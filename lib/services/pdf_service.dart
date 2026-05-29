import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdf/pdf.dart' hide PdfDocument;
import 'package:pdf/widgets.dart' as pw;
import '../models/pdf_annotation.dart';
import 'editor_state.dart';

class PdfService {
  // ── Rasterizza una pagina come immagine PNG ──
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
    final uiImage = await pdfImage.createImageIfNotAvailable();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    canvas.drawImage(uiImage, Offset.zero, Paint());
    final picture = recorder.endRecording();
    final img = await picture.toImage(width, height);
    final pngData = await img.toByteData(format: ui.ImageByteFormat.png);
    return pngData!.buffer.asUint8List();
  }

  // ── Rasterizza una pagina con annotazioni baked (inclusa redazione sicura) ──
  static Future<Uint8List> _renderPageWithAnnotations(
    PdfDocument doc,
    int pageIndex,
    List<PdfAnnotation> annotations, {
    double scale = 2.5,
  }) async {
    final page = doc.pages[pageIndex];
    final width  = (page.width  * scale).toInt();
    final height = (page.height * scale).toInt();
    final sz = Size(width.toDouble(), height.toDouble());

    final pdfImage = await page.render(
      fullWidth:  width.toDouble(),
      fullHeight: height.toDouble(),
    );
    final uiImage = await pdfImage.createImageIfNotAvailable();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    canvas.drawImage(uiImage, Offset.zero, Paint());

    // Bake tutte le annotazioni della pagina
    final pageAnns = annotations.where((a) => a.page == pageIndex + 1).toList();
    for (final ann in pageAnns) {
      await _drawAnnotation(canvas, sz, ann, scale);
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(width, height);
    final pngData = await img.toByteData(format: ui.ImageByteFormat.png);
    return pngData!.buffer.asUint8List();
  }

  static Future<void> _drawAnnotation(
    Canvas canvas,
    Size sz,
    PdfAnnotation ann,
    double scale,
  ) async {
    switch (ann.type) {
      case AnnotationType.redact:
        // Rettangolo nero pieno — il testo sottostante è irrecuperabile
        canvas.drawRect(
          Rect.fromLTWH(ann.x * sz.width, ann.y * sz.height, ann.w * sz.width, ann.h * sz.height),
          Paint()
            ..color = Colors.black
            ..style = PaintingStyle.fill,
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
        final fillPaint = Paint()
          ..color = const Color(0xFFFFD700).withOpacity(0.45)
          ..style = PaintingStyle.fill;
        if (ann.highlightRects != null) {
          for (final r in ann.highlightRects!) {
            canvas.drawRect(
              Rect.fromLTWH(r.left * sz.width, r.top * sz.height, r.width * sz.width, r.height * sz.height),
              fillPaint,
            );
          }
        } else {
          canvas.drawRect(
            Rect.fromLTWH(ann.x * sz.width, ann.y * sz.height, ann.w * sz.width, ann.h * sz.height),
            fillPaint,
          );
        }

      case AnnotationType.draw:
        if (ann.points == null || ann.points!.length < 2) return;
        final path = Path();
        path.moveTo(ann.points![0].dx * sz.width, ann.points![0].dy * sz.height);
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
        final pb = ui.ParagraphBuilder(ui.ParagraphStyle(
          fontSize: fontSize,
          fontFamily: ann.fontFamily,
        ))
          ..pushStyle(ui.TextStyle(
            color: ann.color,
            fontSize: fontSize,
            fontFamily: ann.fontFamily,
          ))
          ..addText(ann.text!);
        final para = pb.build()
          ..layout(ui.ParagraphConstraints(width: sz.width - ann.x * sz.width));
        canvas.drawParagraph(para, Offset(ann.x * sz.width, ann.y * sz.height));

      case AnnotationType.image:
        if (ann.imagePath == null) return;
        try {
          final bytes = await File(ann.imagePath!).readAsBytes();
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          final destRect = Rect.fromLTWH(
            ann.x * sz.width, ann.y * sz.height,
            ann.w * sz.width, ann.h * sz.height,
          );
          paintImage(
            canvas: canvas,
            rect: destRect,
            image: frame.image,
            fit: BoxFit.fill,
          );
        } catch (_) {
          // Immagine non disponibile — salta
        }
    }
  }

  // ── Applica modifiche e salva: bake annotazioni in PDF rasterizzato ──
  // La redazione è sicura perché il PDF risultante è image-based (nessun testo estraibile).
  static Future<File> applyChangesAndSave({
    required File sourceFile,
    required EditorState state,
    required String outputName,
  }) async {
    final dir = await getTemporaryDirectory();
    final outputPath = '${dir.path}/$outputName.pdf';

    final doc = await PdfDocument.openFile(sourceFile.path);
    final pdfDoc = pw.Document();

    for (int pageIdx = 0; pageIdx < doc.pages.length; pageIdx++) {
      final page = doc.pages[pageIdx];

      final imgBytes = await _renderPageWithAnnotations(
        doc, pageIdx, state.annotations,
      );

      pdfDoc.addPage(pw.Page(
        pageFormat: PdfPageFormat(
          page.width  * PdfPageFormat.point,
          page.height * PdfPageFormat.point,
          marginAll: 0,
        ),
        build: (_) => pw.Image(
          pw.MemoryImage(imgBytes),
          fit: pw.BoxFit.fill,
        ),
      ));
    }

    final pdfBytes = await pdfDoc.save();
    await File(outputPath).writeAsBytes(pdfBytes);

    doc.dispose();
    return File(outputPath);
  }

  // ── Converti pagine in immagini (PNG/JPG) ──
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

  // ── Estrai testo strutturato da una pagina ──
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
