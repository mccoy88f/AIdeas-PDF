import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import '../services/editor_state.dart';
import '../utils/app_theme.dart';

class PageSidebar extends StatefulWidget {
  final PdfDocument? document;
  final Future<void> Function(int from, int to) onReorder;
  final Future<void> Function(int page) onDeletePage;

  const PageSidebar({
    super.key,
    required this.document,
    required this.onReorder,
    required this.onDeletePage,
  });

  @override
  State<PageSidebar> createState() => _PageSidebarState();
}

class _PageSidebarState extends State<PageSidebar> {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<EditorState>();
    final doc = widget.document;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: state.sidebarVisible ? 160 : 0,
      child: state.sidebarVisible
        ? Container(
            decoration: BoxDecoration(
              color: state.isDark ? AppTheme.s1 : AppTheme.ls1,
              border: Border(
                right: BorderSide(
                  color: state.isDark ? AppTheme.border : AppTheme.lborder,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle('PAGINE'),
                Expanded(
                  child: doc == null
                    ? const SizedBox()
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        itemCount: doc.pages.length,
                        onReorder: (oldIndex, newIndex) {
                          final from = oldIndex + 1;
                          int to = newIndex + 1;
                          if (newIndex > oldIndex) to--;
                          widget.onReorder(from, to);
                        },
                        buildDefaultDragHandles: false,
                        itemBuilder: (ctx, index) {
                          final pageNum = index + 1;
                          return _PageThumb(
                            key: ValueKey(pageNum),
                            document: doc,
                            pageNum: pageNum,
                            isActive: state.currentPage == pageNum,
                            onTap: () => state.goToPage(pageNum),
                            onDelete: () => _confirmDelete(context, pageNum),
                            index: index,
                          );
                        },
                      ),
                ),
              ],
            ),
          )
        : null,
    );
  }

  void _confirmDelete(BuildContext context, int pageNum) {
    final state = context.read<EditorState>();
    if (state.numPages <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Il documento deve avere almeno una pagina')),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.s1,
        title: const Text('Elimina pagina', style: TextStyle(color: AppTheme.textCol)),
        content: Text(
          'Eliminare la pagina $pageNum di ${state.numPages}?\nQuesta azione non è reversibile.',
          style: const TextStyle(color: AppTheme.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            onPressed: () {
              Navigator.pop(context);
              widget.onDeletePage(pageNum);
            },
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
    child: Text(text,
      style: const TextStyle(
        fontSize: 9.5, fontWeight: FontWeight.w700,
        letterSpacing: 0.7, color: AppTheme.muted,
      )),
  );
}

class _PageThumb extends StatefulWidget {
  final PdfDocument document;
  final int pageNum;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final int index;

  const _PageThumb({
    super.key,
    required this.document,
    required this.pageNum,
    required this.isActive,
    required this.onTap,
    required this.onDelete,
    required this.index,
  });

  @override
  State<_PageThumb> createState() => _PageThumbState();
}

class _PageThumbState extends State<_PageThumb> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit:  (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: widget.isActive ? AppTheme.accent : Colors.transparent,
              width: 2,
            ),
            color: AppTheme.s2,
          ),
          child: Stack(
            children: [
              // Miniatura pagina
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: PdfPageView(
                  document: widget.document,
                  pageNumber: widget.pageNum,
                  alignment: Alignment.topCenter,
                ),
              ),

              // Numero pagina
              Positioned(
                bottom: 3, right: 5,
                child: Text(
                  '${widget.pageNum}',
                  style: const TextStyle(
                    fontSize: 9, color: Colors.white70,
                    shadows: [Shadow(blurRadius: 3, color: Colors.black87)],
                    fontFamily: 'monospace',
                  ),
                ),
              ),

              // Drag handle
              if (_hovering)
                Positioned(
                  top: 4, left: 4,
                  child: ReorderableDragStartListener(
                    index: widget.index,
                    child: const Icon(Icons.drag_indicator,
                      size: 14, color: Colors.white54),
                  ),
                ),

              // × elimina
              if (_hovering)
                Positioned(
                  top: -5, right: -5,
                  child: GestureDetector(
                    onTap: widget.onDelete,
                    child: Container(
                      width: 18, height: 18,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.danger,
                      ),
                      child: const Center(
                        child: Text('×', style: TextStyle(
                          color: Colors.white, fontSize: 13,
                          fontWeight: FontWeight.bold, height: 1,
                        )),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
