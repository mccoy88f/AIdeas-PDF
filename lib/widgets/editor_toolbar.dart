import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../services/editor_state.dart';
import '../models/pdf_annotation.dart';
import '../utils/app_theme.dart';

class EditorToolbar extends StatelessWidget {
  final VoidCallback onOpenFile;
  final VoidCallback onAddPdf;
  final VoidCallback onSave;
  final VoidCallback onConvert;
  final VoidCallback onInsertImage;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomFit;
  final VoidCallback onPrevPage;
  final VoidCallback onNextPage;

  const EditorToolbar({
    super.key,
    required this.onOpenFile,
    required this.onAddPdf,
    required this.onSave,
    required this.onConvert,
    required this.onInsertImage,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoomFit,
    required this.onPrevPage,
    required this.onNextPage,
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EditorState>();
    final isDark = state.isDark;
    final bg = isDark ? AppTheme.s1 : AppTheme.ls1;
    final borderC = isDark ? AppTheme.border : AppTheme.lborder;

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: bg,
        border: Border(bottom: BorderSide(color: borderC, width: 1)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            // Logo
            _Logo(),
            _Sep(isDark),

            // File ops
            _TbBtn(icon: Icons.folder_open_outlined, tooltip: 'Apri PDF', onTap: onOpenFile),
            _TbBtn(icon: Icons.add_circle_outline, tooltip: 'Aggiungi PDF', color: AppTheme.accent2,
              onTap: state.pdfFile != null ? onAddPdf : null),
            _TbBtn(icon: Icons.save_outlined, tooltip: 'Salva PDF', color: AppTheme.accent,
              onTap: state.pdfFile != null ? onSave : null),
            _TbBtn(icon: Icons.swap_horiz_rounded, tooltip: 'Converti', color: AppTheme.accent2,
              onTap: state.pdfFile != null ? onConvert : null),
            _Sep(isDark),

            // Tool palette
            _ToolGroup(onInsertImage: onInsertImage),
            _Sep(isDark),

            // Colore
            _ColorRow(),
            _Sep(isDark),

            // Context: font size (solo typewriter)
            if (state.tool == EditorTool.typewriter) ...[
              _FontControls(),
              _Sep(isDark),
            ],

            // Context: spessore (rect, draw)
            if (state.tool == EditorTool.rect || state.tool == EditorTool.draw) ...[
              _LineWidthControl(),
              _Sep(isDark),
            ],

            // Elimina
            _TbBtn(
              icon: Icons.delete_outline,
              tooltip: 'Elimina selezione',
              color: AppTheme.danger,
              onTap: state.selectedId != null ? () => state.deleteSelected() : null,
            ),

            const Spacer(),

            // Tema
            _TbBtn(
              icon: state.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              tooltip: 'Cambia tema',
              onTap: () => state.toggleTheme(),
            ),

            // Sidebar
            _TbBtn(
              icon: Icons.view_sidebar_outlined,
              tooltip: 'Mostra/nascondi pagine',
              onTap: () => state.toggleSidebar(),
            ),
            _Sep(isDark),

            // Zoom
            _TbBtn(icon: Icons.remove, tooltip: 'Zoom out (-)', onTap: onZoomOut),
            _ZoomLabel(zoom: state.zoom),
            _TbBtn(icon: Icons.add, tooltip: 'Zoom in (+)', onTap: onZoomIn),
            _TbBtn(icon: Icons.fit_screen, tooltip: 'Adatta pagina', onTap: onZoomFit),
            _Sep(isDark),

            // Navigazione pagine
            _TbBtn(icon: Icons.chevron_left, tooltip: 'Pagina precedente', onTap: onPrevPage),
            _PageControl(),
            _TbBtn(icon: Icons.chevron_right, tooltip: 'Pagina successiva', onTap: onNextPage),
          ],
        ),
      ),
    );
  }
}

// ── Logo ──────────────────────────────────
class _Logo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Row(children: [
        const Icon(Icons.picture_as_pdf, color: AppTheme.accent, size: 20),
        const SizedBox(width: 6),
        RichText(text: const TextSpan(
          children: [
            TextSpan(text: 'AIdeas', style: TextStyle(
              color: AppTheme.accent, fontWeight: FontWeight.w800,
              fontSize: 14, letterSpacing: -0.5,
            )),
            TextSpan(text: ' PDF', style: TextStyle(
              color: AppTheme.accent2, fontWeight: FontWeight.w800,
              fontSize: 14, letterSpacing: -0.5,
            )),
          ],
        )),
      ]),
    );
  }
}

// ── Separatore ────────────────────────────
class _Sep extends StatelessWidget {
  final bool isDark;
  const _Sep(this.isDark);
  @override
  Widget build(BuildContext context) => Container(
    width: 1, height: 26, margin: const EdgeInsets.symmetric(horizontal: 4),
    color: isDark ? AppTheme.border : AppTheme.lborder,
  );
}

// ── Pulsante toolbar generico ──────────────
class _TbBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? color;
  const _TbBtn({required this.icon, required this.tooltip, this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 32, height: 32,
          alignment: Alignment.center,
          child: Icon(icon, size: 18,
            color: onTap == null
              ? AppTheme.muted.withOpacity(0.4)
              : (color ?? AppTheme.muted),
          ),
        ),
      ),
    );
  }
}

// ── Gruppo tool palette ────────────────────
class _ToolGroup extends StatelessWidget {
  final VoidCallback onInsertImage;
  const _ToolGroup({required this.onInsertImage});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EditorState>();

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.s2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.border),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          _TP(tool: EditorTool.select,     icon: Icons.mouse_outlined,          tip: 'Cursore (V)'),
          _TP(tool: EditorTool.typewriter, icon: Icons.keyboard_outlined,       tip: 'Macchina da scrivere (T)'),
          _TP(tool: EditorTool.editText,   icon: Icons.edit_outlined,           tip: 'Modifica testo e immagini (E)'),
          _TPAction(icon: Icons.image_outlined, tip: 'Inserisci immagine (I)', onTap: onInsertImage),
          _TP(tool: EditorTool.rect,       icon: Icons.crop_square_outlined,    tip: 'Rettangolo (R)'),
          _TP(tool: EditorTool.highlight,  icon: Icons.highlight,               tip: 'Evidenziatore (H)'),
          _TP(tool: EditorTool.draw,       icon: Icons.draw_outlined,           tip: 'Penna (D)'),
        ],
      ),
    );
  }
}

class _TP extends StatelessWidget {
  final EditorTool tool;
  final IconData icon;
  final String tip;
  const _TP({required this.tool, required this.icon, required this.tip});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EditorState>();
    final isActive = state.tool == tool;
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: () => state.setTool(tool),
        borderRadius: BorderRadius.circular(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 30, height: 30,
          decoration: BoxDecoration(
            color: isActive ? AppTheme.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, size: 16,
            color: isActive ? Colors.white : AppTheme.muted),
        ),
      ),
    );
  }
}

class _TPAction extends StatelessWidget {
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  const _TPAction({required this.icon, required this.tip, required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(width: 30, height: 30,
        child: Icon(icon, size: 16, color: AppTheme.muted)),
    ),
  );
}

// ── Color row ─────────────────────────────
class _ColorRow extends StatelessWidget {
  static const presets = [
    Color(0xFF1d1d1b), Color(0xFF2563eb),
    Color(0xFFdc2626), Color(0xFF16a34a), Color(0xFFd97706),
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EditorState>();
    return Row(
      children: [
        ...presets.map((c) => _Swatch(
          color: c,
          selected: state.color == c,
          onTap: () => state.setColor(c),
        )),
        GestureDetector(
          onTap: () => _showColorPicker(context, state),
          child: Container(
            width: 20, height: 20,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const SweepGradient(colors: [
                Colors.red, Colors.orange, Colors.yellow,
                Colors.green, Colors.blue, Colors.purple, Colors.red,
              ]),
              border: Border.all(color: AppTheme.border, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  void _showColorPicker(BuildContext context, EditorState state) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.s1,
        title: const Text('Seleziona colore', style: TextStyle(color: AppTheme.textCol)),
        content: ColorPicker(
          pickerColor: state.color,
          onColorChanged: state.setColor,
          enableAlpha: false,
          labelTypes: const [],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _Swatch({required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 20, height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(
          color: selected ? Colors.white : Colors.transparent,
          width: 2,
        ),
      ),
    ),
  );
}

// ── Font controls ─────────────────────────
class _FontControls extends StatelessWidget {
  static const fonts = ['Helvetica','Times New Roman','Courier','Georgia','Arial'];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EditorState>();
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: AppTheme.s2,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          DropdownButton<String>(
            value: fonts.contains(state.fontFamily) ? state.fontFamily : fonts.first,
            dropdownColor: AppTheme.s2,
            underline: const SizedBox(),
            style: const TextStyle(color: AppTheme.textCol, fontSize: 11),
            items: fonts.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
            onChanged: (f) { if (f != null) state.setFontFamily(f); },
          ),
          Container(width: 1, height: 16, color: AppTheme.border, margin: const EdgeInsets.symmetric(horizontal: 4)),
          SizedBox(
            width: 36,
            child: TextField(
              controller: TextEditingController(text: state.fontSize.toInt().toString()),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textCol, fontSize: 11, fontFamily: 'monospace'),
              decoration: const InputDecoration(border: InputBorder.none, isDense: true),
              keyboardType: TextInputType.number,
              onSubmitted: (v) {
                final d = double.tryParse(v);
                if (d != null) state.setFontSize(d.clamp(6, 96));
              },
            ),
          ),
          const Text('pt', style: TextStyle(color: AppTheme.muted, fontSize: 9)),
        ],
      ),
    );
  }
}

// ── Line width ────────────────────────────
class _LineWidthControl extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<EditorState>();
    return Row(
      children: [
        const Text('sp', style: TextStyle(color: AppTheme.muted, fontSize: 10)),
        const SizedBox(width: 4),
        SizedBox(
          width: 80,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              min: 1, max: 18,
              value: state.lineWidth,
              activeColor: AppTheme.accent,
              onChanged: state.setLineWidth,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Zoom label ────────────────────────────
class _ZoomLabel extends StatelessWidget {
  final double zoom;
  const _ZoomLabel({required this.zoom});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 44,
    child: Text('${(zoom * 100).round()}%',
      textAlign: TextAlign.center,
      style: const TextStyle(color: AppTheme.muted, fontSize: 11, fontFamily: 'monospace')),
  );
}

// ── Page control ──────────────────────────
class _PageControl extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<EditorState>();
    return Row(
      children: [
        SizedBox(
          width: 36,
          child: TextField(
            controller: TextEditingController(text: state.currentPage.toString()),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textCol, fontSize: 11, fontFamily: 'monospace'),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
            ),
            keyboardType: TextInputType.number,
            onSubmitted: (v) {
              final n = int.tryParse(v);
              if (n != null) state.goToPage(n);
            },
          ),
        ),
        const SizedBox(width: 4),
        Text('/ ${state.numPages}',
          style: const TextStyle(color: AppTheme.muted, fontSize: 11, fontFamily: 'monospace')),
      ],
    );
  }
}
