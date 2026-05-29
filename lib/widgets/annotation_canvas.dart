import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/pdf_annotation.dart';
import '../services/editor_state.dart';
import '../utils/app_theme.dart';

class AnnotationCanvas extends StatefulWidget {
  final Size pageSize; // dimensioni reali del PDF in punti
  final double zoom;

  const AnnotationCanvas({
    super.key,
    required this.pageSize,
    required this.zoom,
  });

  @override
  State<AnnotationCanvas> createState() => _AnnotationCanvasState();
}

class _AnnotationCanvasState extends State<AnnotationCanvas> {
  // Annotazione in corso di creazione
  PdfAnnotation? _live;
  Offset? _startPos;

  // Testo in corso di inserimento (typewriter)
  OverlayEntry? _textEntry;

  Offset _toNorm(Offset pos) => Offset(
    pos.dx / (widget.pageSize.width  * widget.zoom),
    pos.dy / (widget.pageSize.height * widget.zoom),
  );

  Offset _toCanvas(Offset norm) => Offset(
    norm.dx * widget.pageSize.width  * widget.zoom,
    norm.dy * widget.pageSize.height * widget.zoom,
  );

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EditorState>();
    final currentAnns = state.annotations
      .where((a) => a.page == state.currentPage)
      .toList();

    return GestureDetector(
      onTapDown: (d) => _onTapDown(d.localPosition, state),
      onPanStart: (d) => _onPanStart(d.localPosition, state),
      onPanUpdate: (d) => _onPanUpdate(d.localPosition, state),
      onPanEnd: (_) => _onPanEnd(state),
      child: CustomPaint(
        painter: _AnnotationPainter(
          annotations: currentAnns,
          live: _live,
          selectedId: state.selectedId,
          zoom: widget.zoom,
          pageSize: widget.pageSize,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  void _onTapDown(Offset pos, EditorState state) {
    final norm = _toNorm(pos);

    if (state.tool == EditorTool.select) {
      // Hit test annotazioni
      final hit = _hitTest(norm, state);
      state.selectAnnotation(hit?.id);
      return;
    }

    if (state.tool == EditorTool.typewriter) {
      _showTypewriterInput(pos, norm, state);
    }
  }

  void _onPanStart(Offset pos, EditorState state) {
    if (state.tool == EditorTool.select) return;
    if (state.tool == EditorTool.typewriter) return;
    if (state.tool == EditorTool.editText) return;

    _startPos = _toNorm(pos);
    if (state.tool == EditorTool.draw) {
      _live = PdfAnnotation(
        id: _newId(), page: state.currentPage,
        type: AnnotationType.draw,
        points: [_startPos!],
        color: state.color, lineWidth: state.lineWidth,
      );
    }
  }

  void _onPanUpdate(Offset pos, EditorState state) {
    if (_startPos == null) return;
    final cur = _toNorm(pos);
    final x = min(_startPos!.dx, cur.dx);
    final y = min(_startPos!.dy, cur.dy);
    final w = (_startPos!.dx - cur.dx).abs();
    final h = (_startPos!.dy - cur.dy).abs();

    setState(() {
      if (state.tool == EditorTool.rect) {
        _live = PdfAnnotation(
          id: 'live', page: state.currentPage,
          type: AnnotationType.rect,
          x: x, y: y, w: w, h: h,
          color: state.color, lineWidth: state.lineWidth,
        );
      } else if (state.tool == EditorTool.highlight) {
        _live = PdfAnnotation(
          id: 'live', page: state.currentPage,
          type: AnnotationType.highlight,
          x: x, y: y, w: w, h: h,
          color: const Color(0xFFFFD700),
        );
      } else if (state.tool == EditorTool.draw && _live != null) {
        _live!.points!.add(cur);
      }
    });
  }

  void _onPanEnd(EditorState state) {
    if (_live == null) return;
    final a = _live!;
    _live = null;
    _startPos = null;

    // Scarta se troppo piccolo
    if ((a.type == AnnotationType.rect || a.type == AnnotationType.highlight) &&
        (a.w < 0.005 || a.h < 0.005)) {
      setState(() {});
      return;
    }
    if (a.type == AnnotationType.draw && (a.points?.length ?? 0) < 2) {
      setState(() {});
      return;
    }

    state.addAnnotation(a);
    setState(() {});
  }

  PdfAnnotation? _hitTest(Offset norm, EditorState state) {
    final anns = state.annotations
      .where((a) => a.page == state.currentPage)
      .toList().reversed;
    for (final a in anns) {
      if (a.type == AnnotationType.rect || a.type == AnnotationType.highlight) {
        if (norm.dx >= a.x && norm.dx <= a.x + a.w &&
            norm.dy >= a.y && norm.dy <= a.y + a.h) return a;
      } else if (a.type == AnnotationType.text) {
        final tw = (a.text?.length ?? 0) * a.fontSize * 0.006;
        final th = a.fontSize * 0.014;
        if (norm.dx >= a.x && norm.dx <= a.x + tw &&
            norm.dy >= a.y && norm.dy <= a.y + th) return a;
      } else if (a.type == AnnotationType.draw && a.points != null) {
        for (int i = 0; i < a.points!.length - 1; i++) {
          if (_distToSegment(norm, a.points![i], a.points![i + 1]) < 0.008) return a;
        }
      }
    }
    return null;
  }

  double _distToSegment(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx; final dy = b.dy - a.dy;
    final l2 = dx * dx + dy * dy;
    if (l2 == 0) return (p - a).distance;
    final t = ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / l2;
    final tc = t.clamp(0.0, 1.0);
    return (p - Offset(a.dx + tc * dx, a.dy + tc * dy)).distance;
  }

  void _showTypewriterInput(Offset canvasPos, Offset norm, EditorState state) {
    // Mostra un dialog compatto per inserire il testo
    final ctrl = TextEditingController();
    final renderBox = context.findRenderObject() as RenderBox;
    final globalPos = renderBox.localToGlobal(canvasPos);

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (_) => _TypewriterDialog(
        position: globalPos,
        controller: ctrl,
        color: state.color,
        fontSize: state.fontSize * widget.zoom,
        fontFamily: state.fontFamily,
        onSubmit: (text) {
          if (text.trim().isNotEmpty) {
            state.addAnnotation(PdfAnnotation(
              id: _newId(),
              page: state.currentPage,
              type: AnnotationType.text,
              x: norm.dx, y: norm.dy,
              text: text,
              fontSize: state.fontSize,
              fontFamily: state.fontFamily,
              color: state.color,
            ));
          }
        },
      ),
    );
  }
}

// ── Dialog typewriter ─────────────────────
class _TypewriterDialog extends StatelessWidget {
  final Offset position;
  final TextEditingController controller;
  final Color color;
  final double fontSize;
  final String fontFamily;
  final ValueChanged<String> onSubmit;

  const _TypewriterDialog({
    required this.position,
    required this.controller,
    required this.color,
    required this.fontSize,
    required this.fontFamily,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: position.dx.clamp(0, MediaQuery.of(context).size.width - 250),
          top:  position.dy.clamp(0, MediaQuery.of(context).size.height - 120),
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(minWidth: 120, maxWidth: 300),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                border: Border(bottom: BorderSide(color: AppTheme.accent, width: 2)),
              ),
              child: TextField(
                controller: controller,
                autofocus: true,
                maxLines: null,
                style: TextStyle(
                  color: color,
                  fontSize: fontSize,
                  fontFamily: fontFamily,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  isDense: true,
                ),
                onSubmitted: (v) {
                  onSubmit(v);
                  Navigator.pop(context);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Painter annotazioni ───────────────────
class _AnnotationPainter extends CustomPainter {
  final List<PdfAnnotation> annotations;
  final PdfAnnotation? live;
  final String? selectedId;
  final double zoom;
  final Size pageSize;

  const _AnnotationPainter({
    required this.annotations,
    required this.live,
    required this.selectedId,
    required this.zoom,
    required this.pageSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final a in annotations) _drawAnn(canvas, size, a, a.id == selectedId);
    if (live != null) _drawAnn(canvas, size, live!, false);
  }

  Offset _p(double nx, double ny, Size sz) => Offset(nx * sz.width, ny * sz.height);

  void _drawAnn(Canvas canvas, Size sz, PdfAnnotation a, bool sel) {
    final paint = Paint()
      ..color = a.color
      ..strokeWidth = a.lineWidth
      ..style = PaintingStyle.stroke;

    if (a.type == AnnotationType.rect) {
      final r = Rect.fromLTWH(
        a.x * sz.width, a.y * sz.height,
        a.w * sz.width, a.h * sz.height,
      );
      canvas.drawRect(r, paint);
      if (sel) _drawSelBox(canvas, r.inflate(3));
    } else if (a.type == AnnotationType.highlight) {
      final fillPaint = Paint()
        ..color = const Color(0xFFFFD700).withOpacity(0.38)
        ..style = PaintingStyle.fill;
      if (a.highlightRects != null) {
        for (final r in a.highlightRects!) {
          final cr = Rect.fromLTWH(
            r.left * sz.width, r.top * sz.height,
            r.width * sz.width, r.height * sz.height,
          );
          canvas.drawRect(cr, fillPaint);
        }
      } else {
        canvas.drawRect(
          Rect.fromLTWH(a.x * sz.width, a.y * sz.height, a.w * sz.width, a.h * sz.height),
          fillPaint,
        );
      }
    } else if (a.type == AnnotationType.text && a.text != null) {
      final tp = TextPainter(
        text: TextSpan(
          text: a.text,
          style: TextStyle(color: a.color, fontSize: a.fontSize * zoom / pageSize.width * sz.width),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, _p(a.x, a.y, sz));
      if (sel) _drawSelBox(canvas, Rect.fromLTWH(
        a.x * sz.width - 3, a.y * sz.height - 3,
        tp.width + 6, tp.height + 6,
      ));
    } else if (a.type == AnnotationType.draw && a.points != null && a.points!.length > 1) {
      final path = Path();
      path.moveTo(a.points![0].dx * sz.width, a.points![0].dy * sz.height);
      for (int i = 1; i < a.points!.length; i++) {
        path.lineTo(a.points![i].dx * sz.width, a.points![i].dy * sz.height);
      }
      canvas.drawPath(path, paint..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
    }
  }

  void _drawSelBox(Canvas canvas, Rect r) {
    final selPaint = Paint()
      ..color = AppTheme.accent
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawRect(r, selPaint);
    // Handles per immagini
  }

  @override
  bool shouldRepaint(_AnnotationPainter old) => true;
}
