import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/core/di/service_locator.dart';
import 'src/core/theme/app_theme.dart';
import 'src/core/theme/theme_provider.dart';
import 'src/features/home/home_screen.dart';
import 'src/features/history/history_screen.dart';
import 'src/features/live/live_screen.dart';
import 'src/features/record/record_screen.dart';
import 'src/features/training/training_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // App stability: Catch unhandled framework exceptions
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('Bandana Framework Error: ${details.exceptionAsString()}');
  };

  // App stability: Prevent crash terminations on unhandled async platform errors
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Bandana Platform Error caught: $error');
    return true; // Mark as handled to keep app running
  };

  // App stability: Graceful widget error fallback
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: const Color(0xFF121212),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.refresh_rounded, color: Color(0xFFFFB74D), size: 44),
              const SizedBox(height: 12),
              const Text(
                'Temporarily Unavailable',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                details.exceptionAsString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  };

  await setupServiceLocator();
  runApp(const ProviderScope(child: BandanaApp()));
}

/// Root application widget.
class BandanaApp extends StatelessWidget {
  const BandanaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeModeManager,
      builder: (context, _) {
        return MaterialApp(
          title: 'Bandana',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeModeManager.themeMode,
          home: const AppShell(),
        );
      },
    );
  }
}

/// Bottom navigation shell with 5 tabs and Android back-gesture stability.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  void _onStartRecording() {
    setState(() => _currentIndex = 2);
  }

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      const HomeScreen(),                                // 0: Home
      LiveScreen(onStartRecording: _onStartRecording),   // 1: Activity / Live Recognition
      const RecordScreen(),                              // 2: Record / Data Collection
      const TrainingScreen(),                            // 3: Train / On-Device ML
      HistoryScreen(onStartRecording: _onStartRecording),// 4: History / Past Sessions
    ];

    // Android back-gesture stability: Swiping back from tabs 1-4 navigates to Home tab
    // rather than abruptly closing the app. Back from Home exits normally.
    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_currentIndex != 0) {
          setState(() => _currentIndex = 0);
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: screens,
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: Theme.of(context).brightness == Brightness.light
                    ? const Color(0xFF1A1A1A).withValues(alpha: 0.1)
                    : const Color(0xFFF9F7F1).withValues(alpha: 0.1),
                width: 1.5,
              ),
            ),
          ),
          child: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              setState(() => _currentIndex = index);
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.directions_run_outlined),
                selectedIcon: Icon(Icons.directions_run),
                label: 'Activity',
              ),
              NavigationDestination(
                icon: Icon(Icons.fiber_manual_record_outlined),
                selectedIcon: Icon(Icons.fiber_manual_record),
                label: 'Record',
              ),
              NavigationDestination(
                icon: Icon(Icons.model_training_outlined),
                selectedIcon: Icon(Icons.model_training),
                label: 'Train',
              ),
              NavigationDestination(
                icon: Icon(Icons.history_outlined),
                selectedIcon: Icon(Icons.history),
                label: 'History',
              ),
            ],
          ),
        ),
      ),
    );
  }
}