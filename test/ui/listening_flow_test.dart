import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_app/data/quran/ayah_row.dart';
import 'package:quran_app/features/listening/listening_warmup_controller.dart';
import 'package:quran_app/features/listening/listening_warmup_screen.dart';
import 'package:quran_app/features/results/results_screen.dart';
import 'package:quran_app/services/search/quran_search_engine.dart';

void main() {
  testWidgets('warmup countdown triggers transcription and navigates to results', (
    WidgetTester tester,
  ) async {
    int startMicCalls = 0;
    int stopMicCalls = 0;
    int transcribeCalls = 0;
    double requestedSeconds = 0;

    final ListeningWarmupController controller = ListeningWarmupController(
      startMic: () async {
        startMicCalls++;
      },
      stopMic: () async {
        stopMicCalls++;
      },
      getLastSecondsPcm16k: (double seconds) {
        requestedSeconds = seconds;
        return Float32List.fromList(List<double>.filled(16000, 0));
      },
      transcribe: (Float32List pcm16k) async {
        transcribeCalls++;
        return 'الله نور السماوات';
      },
      searchGlobal: (String transcript) async => <SearchResult>[_sampleResult()],
      ensureSeedData: () async {},
      warmupDuration: const Duration(seconds: 2),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ListeningWarmupScreen(
          controller: controller,
          resultsScreenBuilder: (_) => const _ResultMarkerScreen(),
          autoLockConfig: const SearchConfig(autoLockMinScore: 99, autoLockMinMargin: 99),
        ),
      ),
    );

    expect(find.text('Listening… (2s)'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Listening… (1s)'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Results Marker'), findsOneWidget);
    expect(transcribeCalls, 1);
    expect(startMicCalls, 1);
    expect(stopMicCalls, 1);
    expect(requestedSeconds, 2);
  });

  testWidgets('tapping a result navigates to live screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResultsScreen(
          transcript: 'الله نور السماوات',
          results: <SearchResult>[_sampleResult()],
          autoLockConfig: const SearchConfig(autoLockMinScore: 99, autoLockMinMargin: 99),
          liveScreenBuilder: (_) => const _LiveMarkerScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Tap to lock'));
    await tester.pumpAndSettle();

    expect(find.text('Live Marker'), findsOneWidget);
  });

  testWidgets('shows processing state after countdown while transcription is running', (
    WidgetTester tester,
  ) async {
    final Completer<String> transcribeCompleter = Completer<String>();

    final ListeningWarmupController controller = ListeningWarmupController(
      startMic: () async {},
      stopMic: () async {},
      getLastSecondsPcm16k: (_) => Float32List.fromList(List<double>.filled(16000, 0)),
      transcribe: (_) => transcribeCompleter.future,
      searchGlobal: (String transcript) async => <SearchResult>[_sampleResult()],
      ensureSeedData: () async {},
      warmupDuration: const Duration(seconds: 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ListeningWarmupScreen(
          controller: controller,
          resultsScreenBuilder: (_) => const _ResultMarkerScreen(),
          autoLockConfig: const SearchConfig(autoLockMinScore: 99, autoLockMinMargin: 99),
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Processing recitation...'), findsOneWidget);

    transcribeCompleter.complete('الله نور السماوات');
    await tester.pumpAndSettle();
    expect(find.text('Results Marker'), findsOneWidget);
  });
}

SearchResult _sampleResult() {
  return SearchResult(
    ayah: const AyahRow(
      id: 3,
      surahNo: 24,
      ayahNo: 35,
      surahNameAr: 'النور',
      textUthmani: 'اللَّهُ نُورُ السَّمَاوَاتِ وَالْأَرْضِ',
      textNorm: 'الله نور السماوات والارض',
    ),
    score: 1.6,
    nUsed: 3,
    matchStartTokenIndex: 0,
    matchEndTokenIndex: 2,
    matchedTokens: const <String>['الله', 'نور', 'السماوات'],
  );
}

class _ResultMarkerScreen extends StatelessWidget {
  const _ResultMarkerScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Results Marker')));
  }
}

class _LiveMarkerScreen extends StatelessWidget {
  const _LiveMarkerScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Live Marker')));
  }
}
