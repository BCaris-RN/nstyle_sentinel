import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol/patrol.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nstyle_sentinel/main.dart';

class _FailingSentinelRepository implements SentinelRepository {
  _FailingSentinelRepository()
    : _appointments = <BookingAppointment>[
        BookingAppointment(
          id: 'pending-approval-test',
          clientName: 'Horror Path Client',
          startTime: DateTime(2026, 3, 1, 13, 0),
          endTime: DateTime(2026, 3, 1, 14, 0),
          status: BookingStatus.pendingApproval,
          version: 7,
          pendingAction: PendingAction.book,
          notes: 'Injected test pending approval',
        ),
      ];

  final List<BookingAppointment> _appointments;
  final StreamController<PendingApprovalNotification> _notifications =
      StreamController<PendingApprovalNotification>.broadcast();

  @override
  Stream<PendingApprovalNotification> get notifications =>
      _notifications.stream;

  @override
  Future<void> confirmAppointment({
    required String appointmentId,
    required int expectedVersion,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    throw StateError('Simulated 500 from Sentinel API');
  }

  @override
  void dispose() {
    unawaited(_notifications.close());
  }

  @override
  Future<List<BookingAppointment>> loadAppointmentsForYear(
    int year, {
    DateTime? lastSeenTime,
    String? lastSeenId,
    int limit = 500,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return _appointments;
  }

  @override
  Future<void> rejectAppointment({
    required String appointmentId,
    required int expectedVersion,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    throw StateError('Simulated 500 from Sentinel API');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  if (!Platform.isAndroid && !Platform.isIOS) {
    testWidgets(
      'Horror Path (desktop fallback): saves DraftStore state before failed approval mutation',
      (tester) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});

        final failingRepo = _FailingSentinelRepository();
        addTearDown(failingRepo.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sentinelRepositoryProvider.overrideWithValue(failingRepo),
            ],
            child: const NStyleSentinelApp(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Toney Approval Queue'), findsOneWidget);
        await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm').first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Confirmation failed. Draft saved for retry:'),
          findsOneWidget,
        );

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('nstyle.pending_approval_draft'), isNotNull);
      },
    );
    return;
  }

  patrolTest(
    'Horror Path: saves DraftStore state before failed approval mutation',
    ($) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final failingRepo = _FailingSentinelRepository();
      addTearDown(failingRepo.dispose);

      await $.pumpWidgetAndSettle(
        ProviderScope(
          overrides: [
            sentinelRepositoryProvider.overrideWithValue(failingRepo),
          ],
          child: const NStyleSentinelApp(),
        ),
      );

      expect(find.text('Toney Approval Queue'), findsOneWidget);
      expect(find.text('Confirm'), findsOneWidget);

      await $(ElevatedButton).containing('Confirm').tap();
      await $.pumpAndSettle();

      expect(
        find.textContaining('Confirmation failed. Draft saved for retry:'),
        findsOneWidget,
      );

      final prefs = await SharedPreferences.getInstance();
      final savedDraft = prefs.getString('nstyle.pending_approval_draft');
      expect(
        savedDraft,
        isNotNull,
        reason:
            'VIOLATION: DraftStore failed to persist recoverable approval input before mutation.',
      );
    },
  );
}
