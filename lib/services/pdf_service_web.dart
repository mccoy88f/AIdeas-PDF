import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import 'package:pdfrx/pdfrx.dart';
import '../models/pdf_annotation.dart';
import 'editor_state.dart';

// ── PdfService — web implementation using MuPDF WASM ─────────────────────────
// On web: dart:io File exists as a stub. We use XFile to read bytes (works
// on web via fetch) and return a File wrapping a blob object-URL.

class PdfService {
  static Future<File> applyChangesAndSave({
    required File sourceFile,
    required EditorState state,
    required String outputName,
  }) async {
    // XFile.readAsBytes() works on web (object-URL fetch) and native (file read)
    final inputBytes = await XFile(sourceFile.path).readAsBytes();
    final modifiedBytes = await _applyWithMuPdf(inputBytes, state);
    final objectUrl = _bytesToObjectUrl(modifiedBytes);
    return File(objectUrl);
  }

  static Future<Uint8List> _applyWithMuPdf(
    Uint8List pdfBytes,
    EditorState state,
  ) async {
    final bridge = globalContext.getProperty('mupdfBridge'.toJS) as JSObject?;
    if (bridge == null) throw Exception('MuPDF WASM bridge non disponibile');
    final ready = bridge.getProperty('ready'.toJS);
    if (ready == null || !(ready as JSBoolean).toDart) {
      throw Exception('MuPDF WASM bridge non pronto');
    }

    final annotationsJson = jsonEncode({
      'annotations': state.annotations.map(_annToMap).toList(),
      'textEdits': state.textEdits.values
          .map((e) => {
                'page': e.page,
                'deleted': e.deleted,
                'origX': e.x,
                'origY': e.y,
                'origWidth': e.width,
                'origFontSize': e.fontSize,
              })
          .toList(),
      'imageEdits': state.imageEdits.values
          .map((e) => {
                'page': e.page,
                'deleted': e.deleted,
                'origX': e.x,
                'origY': e.y,
                'origWidth': e.width,
                'origHeight': e.height,
              })
          .toList(),
    });

    final promise = bridge.callMethod(
      'applyChanges'.toJS,
      pdfBytes.toJS,
      annotationsJson.toJS,
    ) as JSObject;

    final completer = Completer<Uint8List>();
    (promise.callMethod('then'.toJS, ((JSUint8Array result) {
      completer.complete(result.toDart);
      return null.toJS;
    }).toJS) as JSObject).callMethod('catch'.toJS, ((JSAny err) {
      completer.completeError(err.dartify().toString());
      return null.toJS;
    }).toJS);

    return completer.future;
  }

  static Map<String, dynamic> _annToMap(PdfAnnotation ann) => {
        'id': ann.id,
        'page': ann.page,
        'type': ann.type.name,
        'x': ann.x,
        'y': ann.y,
        'w': ann.w,
        'h': ann.h,
        'color': [ann.color.red, ann.color.green, ann.color.blue],
        'lineWidth': ann.lineWidth,
        'fontSize': ann.fontSize,
        if (ann.fontFamily != null) 'fontFamily': ann.fontFamily,
        if (ann.text != null) 'text': ann.text,
        if (ann.points != null)
          'points': ann.points!.map((p) => {'dx': p.dx, 'dy': p.dy}).toList(),
      };

  static String _bytesToObjectUrl(Uint8List bytes) {
    final fn = globalContext.callMethod(
      'eval'.toJS,
      '(function(a){return URL.createObjectURL(new Blob([a],{type:"application/pdf"}));})'.toJS,
    ) as JSFunction;
    return (fn.callAsFunction(null, bytes.toJS) as JSString).toDart;
  }

  // ── Rasterization helpers (used for export, not for redaction on web) ───────

  static Future<Uint8List> rasterizePage(
    PdfDocument doc,
    int pageIndex, {
    double scale = 2.5,
  }) async {
    final page = doc.pages[pageIndex];
    final width = (page.width * scale).toInt();
    final height = (page.height * scale).toInt();
    final img = await page.render(
      fullWidth: width.toDouble(),
      fullHeight: height.toDouble(),
    );
    return img?.pixels ?? Uint8List(0);
  }

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
