import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/editor_state.dart';
import 'screens/editor_screen.dart';
import 'utils/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AIdeasPdfApp());
}

class AIdeasPdfApp extends StatelessWidget {
  const AIdeasPdfApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => EditorState(),
      child: Consumer<EditorState>(
        builder: (_, state, __) => MaterialApp(
          title: 'AIdeas PDF',
          debugShowCheckedModeBanner: false,
          theme:      AppTheme.light(),
          darkTheme:  AppTheme.dark(),
          themeMode:  state.isDark ? ThemeMode.dark : ThemeMode.light,
          home: const EditorScreen(),
        ),
      ),
    );
  }
}
