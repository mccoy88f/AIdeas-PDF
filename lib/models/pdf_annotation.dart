import 'dart:ui';

enum AnnotationType { text, rect, highlight, draw, image, redact }

enum EditorTool { select, typewriter, editText, rect, highlight, draw, image, redact }

class PdfAnnotation {
  final String id;
  int page;
  final AnnotationType type;
  double x, y, w, h;
  String? text;
  String? fontFamily;
  double fontSize;
  Color color;
  double lineWidth;
  List<Offset>? points;
  String? imagePath;
  double aspectRatio;
  List<Rect>? highlightRects;
  bool isSelected;

  PdfAnnotation({
    required this.id,
    required this.page,
    required this.type,
    this.x = 0, this.y = 0, this.w = 0, this.h = 0,
    this.text, this.fontFamily = 'Helvetica', this.fontSize = 14,
    this.color = const Color(0xFF1d1d1b), this.lineWidth = 2,
    this.points, this.imagePath, this.aspectRatio = 1,
    this.highlightRects, this.isSelected = false,
  });
}

class TextBlockEdit {
  int page;
  final int itemIndex;
  String? newText;
  bool deleted;
  double offsetX, offsetY;
  final double origX, origY, origWidth, origFontSize;

  TextBlockEdit({
    required this.page, required this.itemIndex,
    required this.origX, required this.origY,
    required this.origWidth, required this.origFontSize,
    this.newText, this.deleted = false,
    this.offsetX = 0, this.offsetY = 0,
  });
}

class ImageBlockEdit {
  final int page;
  final int itemIndex;
  bool deleted;
  double offsetX, offsetY;
  final double origX, origY, origWidth, origHeight;

  ImageBlockEdit({
    required this.page, required this.itemIndex,
    required this.origX, required this.origY,
    required this.origWidth, required this.origHeight,
    this.deleted = false, this.offsetX = 0, this.offsetY = 0,
  });
}

class PdfTextItem {
  final int index;
  final String text;
  final double x, y, width, height, fontSize;

  const PdfTextItem({
    required this.index, required this.text,
    required this.x, required this.y,
    required this.width, required this.height,
    required this.fontSize,
  });
}
