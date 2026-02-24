import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart' as sfc;

import 'presentation/splash_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: NStyleSentinelApp()));
}

class NStyleSentinelApp extends StatelessWidget {
  const NStyleSentinelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NStyle Sentinel',
      debugShowCheckedModeBanner: false,
      theme: NStyleTheme.theme,
      home: const _EntryGate(),
    );
  }
}

class _EntryGate extends StatefulWidget {
  const _EntryGate();

  @override
  State<_EntryGate> createState() => _EntryGateState();
}

class _EntryGateState extends State<_EntryGate> {
  var _initialized = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: _initialized
          ? const DashboardScreen(key: ValueKey('dashboard'))
          : SplashView(
              key: const ValueKey('splash'),
              onEnter: () {
                setState(() {
                  _initialized = true;
                });
              },
            ),
    );
  }
}

class NStyleTokens {
  static const Color dark = Color(0xFF0B0D10);
  static const Color gold = Color(0xFFD4AF37);
  static const Color steel = Color(0xFF6B778C);
  static const Color panel = Color(0xFF12161C);
  static const Color border = Color(0xFF263142);
  static const double minTouchTarget = 44;
  static const EdgeInsets screenPadding = EdgeInsets.all(16);
}

class NStyleTheme {
  static ThemeData get theme {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: NStyleTokens.gold,
          brightness: Brightness.dark,
        ).copyWith(
          primary: NStyleTokens.gold,
          secondary: NStyleTokens.steel,
          surface: NStyleTokens.panel,
          outline: NStyleTokens.border,
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: NStyleTokens.dark,
      cardColor: NStyleTokens.panel,
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 28,
          height: 1.0,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          height: 1.1,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          height: 1.2,
          fontWeight: FontWeight.w700,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          height: 1.35,
          fontWeight: FontWeight.w500,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(44, NStyleTokens.minTouchTarget),
          backgroundColor: NStyleTokens.gold,
          foregroundColor: NStyleTokens.dark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, NStyleTokens.minTouchTarget),
          side: const BorderSide(color: NStyleTokens.border),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

enum BookingStatus {
  pendingApproval,
  confirmed,
  cancelled,
  rejected;

  String get label => switch (this) {
    BookingStatus.pendingApproval => 'Pending',
    BookingStatus.confirmed => 'Confirmed',
    BookingStatus.cancelled => 'Cancelled',
    BookingStatus.rejected => 'Rejected',
  };
}

enum PendingAction {
  book,
  modify,
  cancel;

  String get label => switch (this) {
    PendingAction.book => 'Book',
    PendingAction.modify => 'Modify',
    PendingAction.cancel => 'Cancel',
  };
}

class BookingAppointment {
  const BookingAppointment({
    required this.id,
    required this.clientName,
    required this.startTime,
    required this.endTime,
    required this.status,
    required this.version,
    this.pendingAction,
    this.notes,
  });

  final String id;
  final String clientName;
  final DateTime startTime;
  final DateTime endTime;
  final BookingStatus status;
  final int version;
  final PendingAction? pendingAction;
  final String? notes;

  BookingAppointment copyWith({
    BookingStatus? status,
    int? version,
    Object? pendingAction = _sentinelNoChange,
    Object? notes = _sentinelNoChange,
  }) {
    return BookingAppointment(
      id: id,
      clientName: clientName,
      startTime: startTime,
      endTime: endTime,
      status: status ?? this.status,
      version: version ?? this.version,
      pendingAction: identical(pendingAction, _sentinelNoChange)
          ? this.pendingAction
          : pendingAction as PendingAction?,
      notes: identical(notes, _sentinelNoChange)
          ? this.notes
          : notes as String?,
    );
  }
}

const Object _sentinelNoChange = Object();

class ApprovalDraft {
  const ApprovalDraft({
    required this.appointmentId,
    required this.expectedVersion,
    required this.savedAt,
  });

  final String appointmentId;
  final int expectedVersion;
  final DateTime savedAt;

  Map<String, dynamic> toJson() => {
    'appointmentId': appointmentId,
    'expectedVersion': expectedVersion,
    'savedAt': savedAt.toIso8601String(),
  };

  static ApprovalDraft? fromJsonString(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    final appointmentId = decoded['appointmentId'];
    final expectedVersion = decoded['expectedVersion'];
    final savedAt = decoded['savedAt'];
    if (appointmentId is! String ||
        expectedVersion is! int ||
        savedAt is! String) {
      return null;
    }
    final parsed = DateTime.tryParse(savedAt);
    if (parsed == null) return null;
    return ApprovalDraft(
      appointmentId: appointmentId,
      expectedVersion: expectedVersion,
      savedAt: parsed,
    );
  }
}

abstract class DraftStore {
  Future<void> save(ApprovalDraft draft);
  Future<ApprovalDraft?> load();
  Future<void> clear();
}

class SharedPreferencesDraftStore implements DraftStore {
  SharedPreferencesDraftStore({this.key = 'nstyle.pending_approval_draft'});

  final String key;

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  @override
  Future<ApprovalDraft?> load() async {
    final prefs = await SharedPreferences.getInstance();
    return ApprovalDraft.fromJsonString(prefs.getString(key));
  }

  @override
  Future<void> save(ApprovalDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(draft.toJson()));
  }
}

class PendingApprovalNotification {
  const PendingApprovalNotification({
    required this.appointmentId,
    required this.action,
    required this.receivedAt,
  });

  final String appointmentId;
  final PendingAction action;
  final DateTime receivedAt;

  String get message =>
      'AI ${action.label.toLowerCase()} request waiting for Toney approval';
}

abstract class SentinelRepository {
  Stream<PendingApprovalNotification> get notifications;
  Future<List<BookingAppointment>> loadAppointmentsForYear(
    int year, {
    DateTime? lastSeenTime,
    String? lastSeenId,
    int limit,
  });

  Future<void> confirmAppointment({
    required String appointmentId,
    required int expectedVersion,
  });

  Future<void> rejectAppointment({
    required String appointmentId,
    required int expectedVersion,
  });

  void dispose();
}

class CircuitBreaker {
  CircuitBreaker({
    this.failureThreshold = 3,
    this.resetAfter = const Duration(seconds: 10),
  });

  final int failureThreshold;
  final Duration resetAfter;
  int _failureCount = 0;
  DateTime? _openedAt;

  bool get isOpen {
    if (_openedAt == null) return false;
    if (DateTime.now().difference(_openedAt!) >= resetAfter) {
      _openedAt = null;
      _failureCount = 0;
      return false;
    }
    return true;
  }

  Future<T> execute<T>(Future<T> Function() operation) async {
    if (isOpen) {
      throw StateError('Circuit breaker open. Retry shortly.');
    }
    try {
      final result = await operation();
      _failureCount = 0;
      return result;
    } catch (_) {
      _failureCount += 1;
      if (_failureCount >= failureThreshold) {
        _openedAt = DateTime.now();
      }
      rethrow;
    }
  }
}

class MockSentinelRepository implements SentinelRepository {
  MockSentinelRepository() {
    _seed();
    _scheduleDemoNotification();
  }

  final CircuitBreaker _circuitBreaker = CircuitBreaker();
  final StreamController<PendingApprovalNotification> _notificationController =
      StreamController<PendingApprovalNotification>.broadcast();
  final List<BookingAppointment> _appointments = <BookingAppointment>[];
  Timer? _demoTimer;

  @override
  Stream<PendingApprovalNotification> get notifications =>
      _notificationController.stream;

  @override
  Future<void> confirmAppointment({
    required String appointmentId,
    required int expectedVersion,
  }) async {
    await _circuitBreaker.execute(() async {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final index = _appointments.indexWhere(
        (item) => item.id == appointmentId,
      );
      if (index < 0) throw StateError('Appointment not found');
      final current = _appointments[index];
      if (current.version != expectedVersion) {
        throw StateError('Optimistic lock conflict');
      }
      _appointments[index] = current.copyWith(
        status: current.pendingAction == PendingAction.cancel
            ? BookingStatus.cancelled
            : BookingStatus.confirmed,
        pendingAction: null,
        version: current.version + 1,
      );
    });
  }

  @override
  Future<void> rejectAppointment({
    required String appointmentId,
    required int expectedVersion,
  }) async {
    await _circuitBreaker.execute(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final index = _appointments.indexWhere(
        (item) => item.id == appointmentId,
      );
      if (index < 0) throw StateError('Appointment not found');
      final current = _appointments[index];
      if (current.version != expectedVersion) {
        throw StateError('Optimistic lock conflict');
      }
      _appointments[index] = current.copyWith(
        status: current.pendingAction == PendingAction.book
            ? BookingStatus.rejected
            : BookingStatus.confirmed,
        pendingAction: null,
        version: current.version + 1,
      );
    });
  }

  @override
  Future<List<BookingAppointment>> loadAppointmentsForYear(
    int year, {
    DateTime? lastSeenTime,
    String? lastSeenId,
    int limit = 500,
  }) async {
    return _circuitBreaker.execute(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final filtered =
          _appointments.where((item) => item.startTime.year == year).toList()
            ..sort((a, b) {
              final byTime = a.startTime.compareTo(b.startTime);
              return byTime != 0 ? byTime : a.id.compareTo(b.id);
            });

      Iterable<BookingAppointment> page = filtered;
      if (lastSeenTime != null && lastSeenId != null) {
        page = filtered.where((item) {
          final timeCompare = item.startTime.compareTo(lastSeenTime);
          return timeCompare > 0 ||
              (timeCompare == 0 && item.id.compareTo(lastSeenId) > 0);
        });
      }
      return page.take(limit).toList(growable: false);
    });
  }

  @override
  void dispose() {
    _demoTimer?.cancel();
    _notificationController.close();
  }

  void emitDemoNotification({PendingAction action = PendingAction.book}) {
    final pending = _appointments.firstWhere(
      (item) => item.status == BookingStatus.pendingApproval,
      orElse: () => _appointments.first,
    );
    _notificationController.add(
      PendingApprovalNotification(
        appointmentId: pending.id,
        action: pending.pendingAction ?? action,
        receivedAt: DateTime.now(),
      ),
    );
  }

  void _scheduleDemoNotification() {
    _demoTimer = Timer(const Duration(seconds: 2), () {
      if (!_notificationController.isClosed) {
        emitDemoNotification();
      }
    });
  }

  void _seed() {
    const names = <String>[
      'Alex',
      'Jordan',
      'Chris',
      'Devin',
      'Morgan',
      'Taylor',
      'Kai',
      'Jules',
    ];

    final now = DateTime.now();
    final year = now.year;
    var counter = 0;

    for (var month = 1; month <= 12; month += 1) {
      for (var slot = 0; slot < 3; slot += 1) {
        final day = 2 + (slot * 7);
        final start = DateTime(year, month, day, 9 + slot * 2, 30);
        _appointments.add(
          BookingAppointment(
            id: 'appt-${year}_${month}_$slot',
            clientName: names[counter % names.length],
            startTime: start,
            endTime: start.add(const Duration(minutes: 45)),
            status: BookingStatus.confirmed,
            version: 1,
            notes: 'Clipper cut',
          ),
        );
        counter += 1;
      }
    }

    final pendingDay = (now.day + 1).clamp(1, 28);
    final pendingStart = DateTime(year, now.month, pendingDay, 13);
    _appointments.add(
      BookingAppointment(
        id: 'pending-approval-1',
        clientName: 'Walk-in Request',
        startTime: pendingStart,
        endTime: pendingStart.add(const Duration(hours: 1)),
        status: BookingStatus.pendingApproval,
        pendingAction: PendingAction.book,
        version: 3,
        notes: 'AI agent hold: haircut + beard lineup',
      ),
    );
  }
}

class DashboardState {
  const DashboardState({
    required this.year,
    required this.appointments,
    required this.loading,
    required this.busyApprovalIds,
    this.errorMessage,
    this.lastNotification,
    this.draft,
  });

  factory DashboardState.initial() => DashboardState(
    year: DateTime.now().year,
    appointments: const <BookingAppointment>[],
    loading: true,
    busyApprovalIds: const <String>{},
  );

  final int year;
  final List<BookingAppointment> appointments;
  final bool loading;
  final Set<String> busyApprovalIds;
  final String? errorMessage;
  final PendingApprovalNotification? lastNotification;
  final ApprovalDraft? draft;

  List<BookingAppointment> get pendingApprovals =>
      appointments
          .where((item) => item.status == BookingStatus.pendingApproval)
          .toList(growable: false)
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

  DashboardState copyWith({
    int? year,
    List<BookingAppointment>? appointments,
    bool? loading,
    Set<String>? busyApprovalIds,
    Object? errorMessage = _sentinelNoChange,
    Object? lastNotification = _sentinelNoChange,
    Object? draft = _sentinelNoChange,
  }) {
    return DashboardState(
      year: year ?? this.year,
      appointments: appointments ?? this.appointments,
      loading: loading ?? this.loading,
      busyApprovalIds: busyApprovalIds ?? this.busyApprovalIds,
      errorMessage: identical(errorMessage, _sentinelNoChange)
          ? this.errorMessage
          : errorMessage as String?,
      lastNotification: identical(lastNotification, _sentinelNoChange)
          ? this.lastNotification
          : lastNotification as PendingApprovalNotification?,
      draft: identical(draft, _sentinelNoChange)
          ? this.draft
          : draft as ApprovalDraft?,
    );
  }
}

final draftStoreProvider = Provider<DraftStore>(
  (ref) => SharedPreferencesDraftStore(),
);

final sentinelRepositoryProvider = Provider<SentinelRepository>((ref) {
  final repo = MockSentinelRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

final dashboardControllerProvider =
    StateNotifierProvider<DashboardController, DashboardState>((ref) {
      return DashboardController(
        repository: ref.watch(sentinelRepositoryProvider),
        draftStore: ref.watch(draftStoreProvider),
      );
    });

class DashboardController extends StateNotifier<DashboardState> {
  DashboardController({
    required SentinelRepository repository,
    required DraftStore draftStore,
  }) : _repository = repository,
       _draftStore = draftStore,
       super(DashboardState.initial()) {
    _notificationSub = _repository.notifications.listen(_handleNotification);
    unawaited(hydrate());
  }

  final SentinelRepository _repository;
  final DraftStore _draftStore;
  StreamSubscription<PendingApprovalNotification>? _notificationSub;

  Future<void> hydrate() async {
    state = state.copyWith(loading: true, errorMessage: null);
    try {
      final draft = await _draftStore.load();
      final appointments = await _repository.loadAppointmentsForYear(
        state.year,
      );
      state = state.copyWith(
        appointments: appointments,
        loading: false,
        draft: draft,
        errorMessage: null,
      );
    } catch (error) {
      state = state.copyWith(
        loading: false,
        errorMessage: 'Dashboard load failed: $error',
      );
    }
  }

  Future<void> refresh() => hydrate();

  Future<void> loadYear(int year) async {
    if (year == state.year) return;
    state = state.copyWith(year: year);
    await hydrate();
  }

  Future<void> confirmPending(BookingAppointment appointment) =>
      _applyApprovalDecision(appointment: appointment, approve: true);

  Future<void> rejectPending(BookingAppointment appointment) =>
      _applyApprovalDecision(appointment: appointment, approve: false);

  Future<void> _applyApprovalDecision({
    required BookingAppointment appointment,
    required bool approve,
  }) async {
    final nextBusyIds = Set<String>.from(state.busyApprovalIds)
      ..add(appointment.id);
    final draft = ApprovalDraft(
      appointmentId: appointment.id,
      expectedVersion: appointment.version,
      savedAt: DateTime.now(),
    );
    state = state.copyWith(
      busyApprovalIds: nextBusyIds,
      draft: draft,
      errorMessage: null,
    );
    await _draftStore.save(draft);

    try {
      if (approve) {
        await _repository.confirmAppointment(
          appointmentId: appointment.id,
          expectedVersion: appointment.version,
        );
      } else {
        await _repository.rejectAppointment(
          appointmentId: appointment.id,
          expectedVersion: appointment.version,
        );
      }
      await _draftStore.clear();
      await hydrate();
    } catch (error) {
      state = state.copyWith(
        errorMessage: approve
            ? 'Confirmation failed. Draft saved for retry: $error'
            : 'Rejection failed. Draft saved for retry: $error',
      );
    } finally {
      final clearedBusyIds = Set<String>.from(state.busyApprovalIds)
        ..remove(appointment.id);
      state = state.copyWith(busyApprovalIds: clearedBusyIds);
    }
  }

  void clearError() {
    state = state.copyWith(errorMessage: null);
  }

  void _handleNotification(PendingApprovalNotification notification) {
    state = state.copyWith(lastNotification: notification);
    unawaited(refresh());
  }

  @override
  void dispose() {
    _notificationSub?.cancel();
    super.dispose();
  }
}

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardControllerProvider);
    final controller = ref.read(dashboardControllerProvider.notifier);
    final repo = ref.watch(sentinelRepositoryProvider);

    return SentinelNotificationListener(
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: NStyleTokens.screenPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(
                  year: state.year,
                  onPrevYear: () => controller.loadYear(state.year - 1),
                  onNextYear: () => controller.loadYear(state.year + 1),
                  onRefresh: controller.refresh,
                  onSimulatePush: repo is MockSentinelRepository
                      ? () => repo.emitDemoNotification(
                          action: PendingAction.modify,
                        )
                      : null,
                ),
                const SizedBox(height: 12),
                if (state.draft != null)
                  _DraftRecoveryBanner(draft: state.draft!),
                if (state.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ErrorBanner(
                      message: state.errorMessage!,
                      onTap: controller.clearError,
                    ),
                  ),
                PendingApprovalPanel(
                  appointments: state.pendingApprovals,
                  busyApprovalIds: state.busyApprovalIds,
                  onConfirm: controller.confirmPending,
                  onReject: controller.rejectPending,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: YearCalendarGrid(
                    year: state.year,
                    loading: state.loading,
                    appointments: state.appointments,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SentinelNotificationListener extends ConsumerStatefulWidget {
  const SentinelNotificationListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SentinelNotificationListener> createState() =>
      _SentinelNotificationListenerState();
}

class _SentinelNotificationListenerState
    extends ConsumerState<SentinelNotificationListener> {
  StreamSubscription<PendingApprovalNotification>? _subscription;

  @override
  void initState() {
    super.initState();
    final repo = ref.read(sentinelRepositoryProvider);
    _subscription = repo.notifications.listen((notification) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: NStyleTokens.panel,
          content: Text(notification.message),
        ),
      );
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Header extends StatelessWidget {
  const _Header({
    required this.year,
    required this.onPrevYear,
    required this.onNextYear,
    required this.onRefresh,
    this.onSimulatePush,
  });

  final int year;
  final VoidCallback onPrevYear;
  final VoidCallback onNextYear;
  final Future<void> Function() onRefresh;
  final VoidCallback? onSimulatePush;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        Text(
          'NStyle Sentinel',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(color: NStyleTokens.gold),
        ),
        _TouchIconButton(
          tooltip: 'Previous year',
          icon: Icons.chevron_left,
          onPressed: onPrevYear,
        ),
        Text('$year', style: Theme.of(context).textTheme.titleLarge),
        _TouchIconButton(
          tooltip: 'Next year',
          icon: Icons.chevron_right,
          onPressed: onNextYear,
        ),
        ElevatedButton(
          onPressed: () => unawaited(onRefresh()),
          child: const Text('Refresh'),
        ),
        if (onSimulatePush != null)
          OutlinedButton(
            onPressed: onSimulatePush,
            child: const Text('Simulate Push'),
          ),
      ],
    );
  }
}

class _TouchIconButton extends StatelessWidget {
  const _TouchIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, color: NStyleTokens.gold),
      constraints: const BoxConstraints(
        minWidth: NStyleTokens.minTouchTarget,
        minHeight: NStyleTokens.minTouchTarget,
      ),
      style: IconButton.styleFrom(
        backgroundColor: NStyleTokens.panel,
        side: const BorderSide(color: NStyleTokens.border),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onTap});

  final String message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.red.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(message, style: const TextStyle(color: Colors.white)),
        ),
      ),
    );
  }
}

class _DraftRecoveryBanner extends StatelessWidget {
  const _DraftRecoveryBanner({required this.draft});

  final ApprovalDraft draft;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: NStyleTokens.gold.withValues(alpha: 0.12),
          border: Border.all(color: NStyleTokens.gold.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'Recovery draft saved for ${draft.appointmentId} '
            '(v${draft.expectedVersion}) at ${_timeLabel(draft.savedAt)}.',
          ),
        ),
      ),
    );
  }
}

class PendingApprovalPanel extends StatelessWidget {
  const PendingApprovalPanel({
    super.key,
    required this.appointments,
    required this.busyApprovalIds,
    required this.onConfirm,
    required this.onReject,
  });

  final List<BookingAppointment> appointments;
  final Set<String> busyApprovalIds;
  final Future<void> Function(BookingAppointment appointment) onConfirm;
  final Future<void> Function(BookingAppointment appointment) onReject;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Toney Approval Queue',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(width: 8),
                _StatusPill(
                  text: '${appointments.length} pending',
                  color: NStyleTokens.gold,
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (appointments.isEmpty)
              const Text(
                'No pending approvals. Incoming AI requests will appear here.',
              )
            else
              ...appointments.take(3).map((appointment) {
                final busy = busyApprovalIds.contains(appointment.id);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ApprovalQueueTile(
                    appointment: appointment,
                    busy: busy,
                    onConfirm: () => onConfirm(appointment),
                    onReject: () => onReject(appointment),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _ApprovalQueueTile extends StatelessWidget {
  const _ApprovalQueueTile({
    required this.appointment,
    required this.busy,
    required this.onConfirm,
    required this.onReject,
  });

  final BookingAppointment appointment;
  final bool busy;
  final Future<void> Function() onConfirm;
  final Future<void> Function() onReject;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: NStyleTokens.dark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NStyleTokens.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    appointment.clientName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _StatusPill(
                  text:
                      '${appointment.pendingAction?.label ?? 'Book'} • v${appointment.version}',
                  color: NStyleTokens.steel,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${_dateLabel(appointment.startTime)} '
              '${_timeLabel(appointment.startTime)} - ${_timeLabel(appointment.endTime)}',
            ),
            if (appointment.notes != null) ...[
              const SizedBox(height: 4),
              Text(
                appointment.notes!,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: busy ? null : () => unawaited(onConfirm()),
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Confirm'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : () => unawaited(onReject()),
                  child: const Text('Reject'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class YearCalendarGrid extends StatelessWidget {
  const YearCalendarGrid({
    super.key,
    required this.year,
    required this.loading,
    required this.appointments,
  });

  final int year;
  final bool loading;
  final List<BookingAppointment> appointments;

  @override
  Widget build(BuildContext context) {
    final monthStarts = List<DateTime>.generate(
      12,
      (index) => DateTime(year, index + 1, 1),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width >= 1320
            ? 3
            : width >= 860
            ? 2
            : 1;

        return Stack(
          children: [
            GridView.builder(
              itemCount: monthStarts.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: crossAxisCount == 1 ? 1.4 : 1.08,
              ),
              itemBuilder: (context, index) {
                final month = monthStarts[index];
                final monthAppointments = appointments
                    .where(
                      (item) =>
                          item.startTime.year == month.year &&
                          item.startTime.month == month.month,
                    )
                    .toList(growable: false);
                return MonthCalendarCard(
                  monthStart: month,
                  appointments: monthAppointments,
                );
              },
            ),
            if (loading)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        );
      },
    );
  }
}

class MonthCalendarCard extends StatelessWidget {
  const MonthCalendarCard({
    super.key,
    required this.monthStart,
    required this.appointments,
  });

  final DateTime monthStart;
  final List<BookingAppointment> appointments;

  @override
  Widget build(BuildContext context) {
    final dataSource = AppointmentCalendarDataSource(appointments);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_monthName(monthStart.month)} ${monthStart.year}',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: NStyleTokens.gold),
                  ),
                ),
                _StatusPill(
                  text: '${appointments.length} appts',
                  color: NStyleTokens.steel,
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: sfc.SfCalendar(
                view: sfc.CalendarView.month,
                dataSource: dataSource,
                initialDisplayDate: monthStart,
                showNavigationArrow: false,
                headerHeight: 0,
                todayHighlightColor: NStyleTokens.gold,
                backgroundColor: Colors.transparent,
                cellBorderColor: NStyleTokens.border.withValues(alpha: 0.4),
                monthViewSettings: const sfc.MonthViewSettings(
                  appointmentDisplayMode:
                      sfc.MonthAppointmentDisplayMode.appointment,
                  showAgenda: false,
                  navigationDirection: sfc.MonthNavigationDirection.vertical,
                ),
                onTap: (details) {
                  final tapped = details.appointments;
                  if (tapped == null || tapped.isEmpty) return;
                  final appointment = tapped.first;
                  final messenger = ScaffoldMessenger.maybeOf(context);
                  if (appointment is sfc.Appointment && messenger != null) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          '${appointment.subject} • ${_timeLabel(appointment.startTime)}',
                        ),
                      ),
                    );
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AppointmentCalendarDataSource extends sfc.CalendarDataSource {
  AppointmentCalendarDataSource(List<BookingAppointment> records) {
    appointments = records
        .map(
          (record) => sfc.Appointment(
            startTime: record.startTime,
            endTime: record.endTime,
            subject: '${record.clientName} (${record.status.label})',
            color: _colorForStatus(record.status),
            notes: record.notes,
          ),
        )
        .toList(growable: false);
  }

  static Color _colorForStatus(BookingStatus status) {
    return switch (status) {
      BookingStatus.pendingApproval => const Color(0xFFE6C25A),
      BookingStatus.confirmed => const Color(0xFF3FA46A),
      BookingStatus.cancelled => const Color(0xFF8B99A8),
      BookingStatus.rejected => const Color(0xFFC65B5B),
    };
  }
}

String _monthName(int month) {
  const names = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return names[month - 1];
}

String _dateLabel(DateTime dateTime) =>
    '${_monthName(dateTime.month).substring(0, 3)} ${dateTime.day}, ${dateTime.year}';

String _timeLabel(DateTime dateTime) {
  final hour24 = dateTime.hour;
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final suffix = hour24 >= 12 ? 'PM' : 'AM';
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  return '$hour12:$minute $suffix';
}
