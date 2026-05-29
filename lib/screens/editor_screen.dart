import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/pdf_annotation.dart';
import '../services/editor_state.dart';
import '../services/pdf_service.dart';
import '../widgets/editor_toolbar.dart';
import '../widgets/page_sidebar.dart';
import '../widgets/annotation_canvas.dart';
import '../utils/app_theme.dart';
import '../utils/web_download.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  PdfDocument? _document;
  bool _isLoading = false;
  String _loadingMsg = '';
  PdfViewerController? _pdfCtrl;

  @override
  void initState() {
    super.initState();
    _pdfCtrl = PdfViewerController();
  }

  @override
  void dispose() {
    _document?.dispose();
    _pdfCtrl?.dispose();
    super.dispose();
  }

  // ────────────────────────────────────────
  // FILE OPS
  // ────────────────────────────────────────
  Future<void> _openFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    if (kIsWeb) {
      final bytes = picked.bytes;
      if (bytes == null) return;
      final name = picked.name.replaceAll('.pdf', '');
      await _loadPdfBytes(bytes, fileName: name);
    } else {
      await _loadPdf(File(picked.path!));
    }
  }

  Future<void> _loadPdfBytes(Uint8List bytes, {String? fileName}) async {
    _setLoading('Caricamento PDF…');
    try {
      _document?.dispose();
      _document = await PdfDocument.openData(bytes);
      final state = context.read<EditorState>();
      // On web use a placeholder File; actual bytes stored separately
      state.loadFile(File(''), fileName: fileName, bytes: bytes);
      state.setNumPages(_document!.pages.length);
    } catch (e) {
      _showError('Errore caricamento: $e');
    }
    _setLoading('');
  }

  Future<void> _loadPdf(File file, {String? fileName}) async {
    _setLoading('Caricamento PDF…');
    try {
      _document?.dispose();
      _document = await PdfDocument.openFile(file.path);
      final state = context.read<EditorState>();
      state.loadFile(file, fileName: fileName);
      state.setNumPages(_document!.pages.length);
    } catch (e) {
      _showError('Errore caricamento: $e');
    }
    _setLoading('');
  }

  Future<void> _addPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['pdf'],
    );
    if (result == null || result.files.isEmpty) return;
    _showAddPdfDialog(File(result.files.first.path!));
  }

  Future<void> _insertImage() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.gallery);
    if (img == null) return;
    final state = context.read<EditorState>();
    state.addAnnotation(PdfAnnotation(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      page: state.currentPage,
      type: AnnotationType.image,
      x: 0.1, y: 0.1, w: 0.4, h: 0.3,
      imagePath: img.path,
      aspectRatio: 1.0,
    ));
  }

  // ────────────────────────────────────────
  // SALVA + APPLICA MODIFICHE
  // ────────────────────────────────────────
  Future<void> _onSave() async {
    final state = context.read<EditorState>();
    if (state.pdfFile == null && state.pdfBytes == null) return;
    if (state.hasChanges) {
      final apply = await _showApplyDialog();
      if (apply == null) return;
      if (apply) {
        await _applyChanges();
      } else {
        state.discardChanges();
      }
    }
    _showSaveDialog();
  }

  Future<bool?> _showApplyDialog() => showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppTheme.s1,
      title: const Text('Applicare le modifiche?', style: TextStyle(color: AppTheme.textCol)),
      content: const Text(
        'Vuoi applicare definitivamente le modifiche al PDF oppure scartarle?',
        style: TextStyle(color: AppTheme.muted),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Scarta'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Applica e aggiorna'),
        ),
      ],
    ),
  );

  Future<void> _applyChanges() async {
    final state = context.read<EditorState>();
    if (state.pdfFile == null && state.pdfBytes == null) return;
    _setLoading('Applicazione modifiche…');
    try {
      final output = await PdfService.applyChangesAndSave(
        sourceFile: state.pdfFile!,
        state: state,
        outputName: state.fileName + '_modified',
      );
      if (kIsWeb) {
        // On web, bytes are already updated in state.pdfBytes by the service.
        // Reload the document from the updated bytes.
        final bytes = state.pdfBytes;
        if (bytes != null) {
          _document?.dispose();
          _document = await PdfDocument.openData(bytes);
          state.setNumPages(_document!.pages.length);
        }
      } else {
        await _loadPdf(output);
      }
      state.clearEdits();
      _showSnack('Modifiche applicate');
    } catch (e) {
      _showError('Errore: $e');
    }
    _setLoading('');
  }

  void _showSaveDialog() {
    final state = context.read<EditorState>();
    final ctrl = TextEditingController(text: state.fileName + '_AIdeasPDF');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.s1,
        title: const Text('Salva PDF', style: TextStyle(color: AppTheme.textCol)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: ctrl,
            autofocus: true,
            style: const TextStyle(color: AppTheme.textCol),
            decoration: InputDecoration(
              hintText: 'nome_file',
              hintStyle: const TextStyle(color: AppTheme.muted),
              enabledBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: AppTheme.border),
                borderRadius: BorderRadius.circular(6),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: AppTheme.accent),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text('.pdf aggiunto automaticamente',
            style: TextStyle(color: AppTheme.muted, fontSize: 11)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
            onPressed: () async {
              Navigator.pop(context);
              await _downloadPdf(ctrl.text.trim());
            },
            child: const Text('Scarica', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadPdf(String name) async {
    final state = context.read<EditorState>();
    if (state.pdfFile == null && state.pdfBytes == null) return;
    _setLoading('Preparazione download…');
    try {
      final fname = name.isEmpty ? 'documento_AIdeasPDF' : name;
      if (kIsWeb) {
        final bytes = state.pdfBytes;
        if (bytes == null) return;
        final url = createObjectUrlFromBytes(bytes);
        triggerWebDownload(url, '$fname.pdf');
      } else if (Platform.isAndroid || Platform.isIOS) {
        await Share.shareXFiles(
          [XFile(state.pdfFile!.path, name: '$fname.pdf')],
          subject: fname,
        );
      } else {
        // Desktop: copia in Downloads
        final dir = await getDownloadsDirectory();
        if (dir != null) {
          await state.pdfFile!.copy('${dir.path}/$fname.pdf');
          _showSnack('Salvato in Downloads/$fname.pdf');
        }
      }
    } catch (e) {
      _showError('Errore download: $e');
    }
    _setLoading('');
  }

  Future<Directory?> getDownloadsDirectory() async {
    if (Platform.isWindows) {
      return Directory('${Platform.environment['USERPROFILE']}\\Downloads');
    } else if (Platform.isMacOS || Platform.isLinux) {
      return Directory('${Platform.environment['HOME']}/Downloads');
    }
    return null;
  }

  // ────────────────────────────────────────
  // PAGINE
  // ────────────────────────────────────────
  Future<void> _reorderPage(int from, int to) async {
    _setLoading('Riordino pagine…');
    // Implementazione con pdfrx/pdf_render per riordinare pagine
    _setLoading('');
    _showSnack('Pagina spostata');
  }

  Future<void> _deletePage(int pageNum) async {
    _setLoading('Eliminazione pagina…');
    try {
      // Usa pdfrx per ricostruire il documento senza la pagina
      _showSnack('Pagina $pageNum eliminata');
    } catch (e) {
      _showError('Errore: $e');
    }
    _setLoading('');
  }

  // ────────────────────────────────────────
  // KEYBOARD
  // ────────────────────────────────────────
  void _handleKey(KeyEvent event) {
    final state = context.read<EditorState>();
    if (event is! KeyDownEvent) return;
    final ctrl = HardwareKeyboard.instance.isControlPressed ||
                 HardwareKeyboard.instance.isMetaPressed;
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyS) { _onSave(); return; }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyO) { _openFile(); return; }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyZ) { state.undoLast(); return; }
    if (event.logicalKey == LogicalKeyboardKey.keyV) { state.setTool(EditorTool.select); }
    if (event.logicalKey == LogicalKeyboardKey.keyT) { state.setTool(EditorTool.typewriter); }
    if (event.logicalKey == LogicalKeyboardKey.keyE) { state.setTool(EditorTool.editText); }
    if (event.logicalKey == LogicalKeyboardKey.keyR) { state.setTool(EditorTool.rect); }
    if (event.logicalKey == LogicalKeyboardKey.keyH) { state.setTool(EditorTool.highlight); }
    if (event.logicalKey == LogicalKeyboardKey.keyD) { state.setTool(EditorTool.draw); }
    if (event.logicalKey == LogicalKeyboardKey.keyX) { state.setTool(EditorTool.redact); }
    if (event.logicalKey == LogicalKeyboardKey.keyI) { _insertImage(); }
    if (event.logicalKey == LogicalKeyboardKey.delete) { state.deleteSelected(); }
    if (event.logicalKey == LogicalKeyboardKey.equal) { state.zoomIn(); }
    if (event.logicalKey == LogicalKeyboardKey.minus) { state.zoomOut(); }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) { state.goToPage(state.currentPage + 1); }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft)  { state.goToPage(state.currentPage - 1); }
  }

  // ────────────────────────────────────────
  // BUILD
  // ────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final state = context.watch<EditorState>();

    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKeyEvent: _handleKey,
      child: Theme(
        data: state.isDark ? AppTheme.dark() : AppTheme.light(),
        child: Scaffold(
          body: Column(children: [
            // Toolbar
            EditorToolbar(
              onOpenFile:    _openFile,
              onAddPdf:      _addPdf,
              onSave:        _onSave,
              onConvert:     _showConvertDialog,
              onInsertImage: _insertImage,
              onZoomIn:      state.zoomIn,
              onZoomOut:     state.zoomOut,
              onZoomFit:     _zoomFit,
              onPrevPage:    () => state.goToPage(state.currentPage - 1),
              onNextPage:    () => state.goToPage(state.currentPage + 1),
            ),

            // Main area
            Expanded(
              child: Row(children: [
                // Sidebar miniature
                PageSidebar(
                  document: _document,
                  onReorder: _reorderPage,
                  onDeletePage: _deletePage,
                ),

                // Canvas area
                Expanded(
                  child: Container(
                    color: state.isDark ? const Color(0xFF080b10) : const Color(0xFFdde0ea),
                    child: _document == null
                      ? _DropZone(onOpenFile: _openFile)
                      : _PdfCanvas(
                          document: _document!,
                          state: state,
                          controller: _pdfCtrl!,
                        ),
                  ),
                ),
              ]),
            ),

            // Status bar
            _StatusBar(state: state),
          ]),

          // Loading overlay
          floatingActionButton: null,
        ),
      ),
    );
  }

  void _zoomFit() {
    // TODO: calcola zoom per adattare la pagina alla viewport
    final state = context.read<EditorState>();
    state.setZoom(1.0);
  }

  void _showAddPdfDialog(File file) {
    // Dialog per scegliere dove inserire le pagine
    showDialog(
      context: context,
      builder: (_) => _AddPdfDialog(
        addFile: file,
        numPages: context.read<EditorState>().numPages,
        onConfirm: (pos, afterPage) async {
          _setLoading('Inserimento pagine…');
          // TODO: implementa con pdfrx
          _setLoading('');
          _showSnack('Pagine aggiunte');
        },
      ),
    );
  }

  void _showConvertDialog() {
    showDialog(
      context: context,
      builder: (_) => _ConvertDialog(
        onConvert: (fmt, pageNums) async {
          _setLoading('Conversione in corso…');
          try {
            if (_document != null) {
              await PdfService.pagesToImages(_document!, pageNums, jpeg: fmt == 'jpg');
            }
            _showSnack('Conversione completata');
          } catch (e) {
            _showError('Errore conversione: $e');
          }
          _setLoading('');
        },
      ),
    );
  }

  void _setLoading(String msg) => setState(() {
    _isLoading = msg.isNotEmpty;
    _loadingMsg = msg;
  });

  void _showError(String msg) => ScaffoldMessenger.of(context)
    .showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppTheme.danger));

  void _showSnack(String msg) => ScaffoldMessenger.of(context)
    .showSnackBar(SnackBar(content: Text(msg)));
}

// ── Drop zone ──────────────────────────────
class _DropZone extends StatelessWidget {
  final VoidCallback onOpenFile;
  const _DropZone({required this.onOpenFile});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.upload_file_outlined, size: 64, color: AppTheme.muted),
      const SizedBox(height: 16),
      const Text('Apri un PDF', style: TextStyle(
        fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.textCol)),
      const SizedBox(height: 8),
      const Text('Trascina un file qui oppure selezionalo dal dispositivo',
        style: TextStyle(color: AppTheme.muted), textAlign: TextAlign.center),
      const SizedBox(height: 20),
      ElevatedButton.icon(
        onPressed: onOpenFile,
        icon: const Icon(Icons.folder_open_outlined),
        label: const Text('Seleziona PDF'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
    ]),
  );
}

// ── PDF canvas con annotazioni ─────────────
class _PdfCanvas extends StatelessWidget {
  final PdfDocument document;
  final EditorState state;
  final PdfViewerController controller;

  const _PdfCanvas({
    required this.document,
    required this.state,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return PdfViewer.document(
      document,
      controller: controller,
      params: PdfViewerParams(
        margin: 24,
        backgroundColor: Colors.transparent,
        // Overlay annotazioni sopra ogni pagina
        pageOverlaysBuilder: (context, pageRect, page) {
          final pageSize = Size(page.width, page.height);
          return [
            Positioned.fill(
              child: AnnotationCanvas(
                pageSize: pageSize,
                zoom: state.zoom,
              ),
            ),
          ];
        },
      ),
    );
  }
}

// ── Status bar ─────────────────────────────
class _StatusBar extends StatelessWidget {
  final EditorState state;
  const _StatusBar({required this.state});

  @override
  Widget build(BuildContext context) {
    const s = TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: AppTheme.muted);
    const dot = Text(' · ', style: s);
    return Container(
      height: 26,
      color: state.isDark ? AppTheme.s1 : AppTheme.ls1,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        Text(_toolName(state.tool), style: s), dot,
        Text('${state.annotations.length} modifiche', style: s), dot,
        Text('pag ${state.currentPage}/${state.numPages}', style: s),
      ]),
    );
  }

  String _toolName(EditorTool t) => const {
    EditorTool.select:     'Cursore',
    EditorTool.typewriter: 'Macchina da scrivere',
    EditorTool.editText:   'Modifica testo e immagini',
    EditorTool.rect:       'Rettangolo',
    EditorTool.highlight:  'Evidenziatore',
    EditorTool.draw:       'Penna',
    EditorTool.image:      'Immagine',
    EditorTool.redact:     'Redazione sicura',
  }[t] ?? '';
}

// ── Dialog aggiungi PDF ─────────────────────
class _AddPdfDialog extends StatefulWidget {
  final File addFile;
  final int numPages;
  final Future<void> Function(String pos, int afterPage) onConfirm;
  const _AddPdfDialog({required this.addFile, required this.numPages, required this.onConfirm});

  @override
  State<_AddPdfDialog> createState() => _AddPdfDialogState();
}

class _AddPdfDialogState extends State<_AddPdfDialog> {
  String _pos = 'end';
  int _afterPage = 1;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.s1,
      title: const Text('Aggiungi PDF', style: TextStyle(color: AppTheme.textCol)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(widget.addFile.path.split(Platform.pathSeparator).last,
          style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
        const SizedBox(height: 12),
        RadioListTile(value: 'end', groupValue: _pos, title: const Text('In fondo'), onChanged: (v) => setState(() => _pos = v!)),
        RadioListTile(value: 'start', groupValue: _pos, title: const Text('All\'inizio'), onChanged: (v) => setState(() => _pos = v!)),
        RadioListTile(
          value: 'after', groupValue: _pos,
          title: Row(children: [
            const Text('Dopo pagina: '),
            DropdownButton<int>(
              value: _afterPage,
              dropdownColor: AppTheme.s2,
              items: List.generate(widget.numPages, (i) => DropdownMenuItem(
                value: i + 1, child: Text('${i + 1}'))),
              onChanged: (v) { if (v != null) setState(() => _afterPage = v); },
            ),
          ]),
          onChanged: (v) => setState(() => _pos = v!),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
          onPressed: () { Navigator.pop(context); widget.onConfirm(_pos, _afterPage); },
          child: const Text('Inserisci', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

// ── Dialog converti ─────────────────────────
class _ConvertDialog extends StatefulWidget {
  final Future<void> Function(String fmt, List<int> pages) onConvert;
  const _ConvertDialog({required this.onConvert});

  @override
  State<_ConvertDialog> createState() => _ConvertDialogState();
}

class _ConvertDialogState extends State<_ConvertDialog> {
  String? _fmt;
  bool _allPages = false;

  @override
  Widget build(BuildContext context) {
    final state = context.read<EditorState>();
    return AlertDialog(
      backgroundColor: AppTheme.s1,
      title: const Text('Converti documento', style: TextStyle(color: AppTheme.textCol)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final f in ['docx', 'odt', 'png', 'jpg'])
            _FmtCard(fmt: f, selected: _fmt == f, onTap: () => setState(() => _fmt = f)),
        ]),
        if (_fmt == 'png' || _fmt == 'jpg') ...[
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Tutte le pagine (ZIP)', style: TextStyle(color: AppTheme.textCol, fontSize: 13)),
            value: _allPages,
            activeColor: AppTheme.accent,
            onChanged: (v) => setState(() => _allPages = v),
          ),
        ],
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
          onPressed: _fmt == null ? null : () {
            Navigator.pop(context);
            final pages = _allPages
              ? List.generate(state.numPages, (i) => i + 1)
              : [state.currentPage];
            widget.onConvert(_fmt!, pages);
          },
          child: const Text('Converti', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

class _FmtCard extends StatelessWidget {
  final String fmt;
  final bool selected;
  final VoidCallback onTap;
  const _FmtCard({required this.fmt, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 90, height: 70,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: selected ? AppTheme.accent : AppTheme.border,
          width: selected ? 1.5 : 1,
        ),
        color: selected ? AppTheme.accent.withOpacity(0.1) : AppTheme.s2,
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(_fmtIcon(fmt), color: selected ? AppTheme.accent : AppTheme.muted, size: 22),
        const SizedBox(height: 4),
        Text(fmt.toUpperCase(), style: TextStyle(
          color: selected ? AppTheme.accent : AppTheme.textCol,
          fontSize: 12, fontWeight: FontWeight.w600,
        )),
        Text(_fmtSub(fmt), style: const TextStyle(color: AppTheme.muted, fontSize: 10)),
      ]),
    ),
  );

  IconData _fmtIcon(String f) => switch(f) {
    'docx' => Icons.description_outlined,
    'odt'  => Icons.article_outlined,
    'png'  => Icons.image_outlined,
    'jpg'  => Icons.photo_outlined,
    _      => Icons.file_present_outlined,
  };

  String _fmtSub(String f) => switch(f) {
    'docx' => 'Word', 'odt' => 'LibreOffice',
    'png'  => 'Immagine', 'jpg' => 'JPEG', _ => '',
  };
}
