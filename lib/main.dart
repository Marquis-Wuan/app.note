import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

final np = FlutterLocalNotificationsPlugin();
const allDays = [1, 2, 3, 4, 5, 6, 7]; // 1 = Senin / Monday ... 7 = Minggu / Sunday

// ---------- Bahasa & tema ----------
const _s = {
  'title': ['Kebiasaan hari ini', "Today's habits"],
  'add': ['Tambah', 'Add'],
  'empty': ['Belum ada kebiasaan.\nTekan Tambah untuk memilih template.', 'No habits yet.\nTap Add to pick a template.'],
  'tpl': ['Template', 'Templates'],
  'custom': ['Buat sendiri', 'Create your own'],
  'name': ['Nama kebiasaan', 'Habit name'],
  'target': ['Target', 'Target'],
  'unit': ['Satuan', 'Unit'],
  'step': ['Per tap', 'Per tap'],
  'remind': ['Pengingat', 'Reminder'],
  'save': ['Simpan', 'Save'],
  'now': ['Waktunya', 'Time for'],
  'settings': ['Pengaturan', 'Settings'],
  'lang': ['Bahasa', 'Language'],
  'theme': ['Tema', 'Theme'],
  'system': ['Sistem', 'System'],
  'light': ['Terang', 'Light'],
  'dark': ['Gelap', 'Dark'],
  'water': ['Minum air', 'Drink water'],
  'workout': ['Workout', 'Workout'],
  'sleep': ['Tidur tepat waktu', 'Sleep on time'],
  'read': ['Baca 15 menit', 'Read 15 min'],
  'session': ['sesi', 'session'],
  'times': ['kali', 'times'],
};
final lang = ValueNotifier<String>('id');
final mode = ValueNotifier<ThemeMode>(ThemeMode.system);
String tr(String k) => _s[k]![lang.value == 'id' ? 0 : 1];

Future<void> saveSettings() async {
  final p = await SharedPreferences.getInstance();
  await p.setString('lang', lang.value);
  await p.setInt('theme', mode.value.index);
}

ThemeData _theme(Brightness b) =>
    ThemeData(colorSchemeSeed: const Color(0xFF0F766E), brightness: b, useMaterial3: true);

// ---------- Data ----------
class Habit {
  String name, unit, date;
  int target, step, done;
  List<String> times; // "HH:mm"
  List<int> days;

  Habit(this.name, this.unit, this.target, this.step, this.times, this.days,
      {this.done = 0, this.date = ''});

  Map<String, dynamic> toJson() => {
        'n': name, 'u': unit, 't': target, 's': step,
        'tm': times, 'd': days, 'x': done, 'dt': date,
      };

  factory Habit.fromJson(Map<String, dynamic> j) => Habit(
        j['n'], j['u'], j['t'], j['s'],
        List<String>.from(j['tm']), List<int>.from(j['d']),
        done: j['x'], date: j['dt']);
}

// Template bawaan. Ubah angkanya di sini kalau ingin pola lain.
List<Habit> templates() => [
      Habit(tr('water'), 'ml', 3000, 250,
          [for (var h = 8; h <= 20; h += 2) '${h.toString().padLeft(2, '0')}:00'],
          allDays),
      Habit(tr('workout'), tr('session'), 1, 1, ['17:00'], [1, 3, 5]), // Sen, Rab, Jum
      Habit(tr('sleep'), tr('times'), 1, 1, ['22:00'], allDays),
      Habit(tr('read'), tr('times'), 1, 1, ['20:00'], allDays),
    ];

String today() {
  final n = DateTime.now();
  return '${n.year}-${n.month}-${n.day}';
}

// ---------- Notifikasi ----------
tz.TZDateTime nextTime(String hm, int? weekday) {
  final p = hm.split(':');
  final now = DateTime.now();
  var d = DateTime(now.year, now.month, now.day, int.parse(p[0]), int.parse(p[1]));
  while (d.isBefore(now) || (weekday != null && d.weekday != weekday)) {
    d = d.add(const Duration(days: 1));
  }
  return tz.TZDateTime.from(d, tz.UTC);
}

Future<void> reschedule(List<Habit> hs) async {
  await np.cancelAll();
  const nd = NotificationDetails(
      android: AndroidNotificationDetails('habit', 'Habit reminders',
          importance: Importance.high, priority: Priority.high));
  var id = 0;
  for (final h in hs) {
    final daily = h.days.length == 7;
    final List<int?> ds = daily ? [null] : List<int?>.from(h.days);
    for (final t in h.times) {
      for (final d in ds) {
        await np.zonedSchedule(
          id: id++,
          title: h.name,
          body: '${tr('now')}: ${h.name}',
          scheduledDate: nextTime(t, d),
          notificationDetails: nd,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents:
              daily ? DateTimeComponents.time : DateTimeComponents.dayOfWeekAndTime,
        );
      }
    }
  }
}

// ---------- Aplikasi ----------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await np.initialize(
      settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher')));
  await np
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
  final p = await SharedPreferences.getInstance();
  lang.value = p.getString('lang') ??
      (PlatformDispatcher.instance.locale.languageCode == 'id' ? 'id' : 'en');
  mode.value = ThemeMode.values[p.getInt('theme') ?? 0]; // 0 = ikuti sistem
  runApp(ListenableBuilder(
    listenable: mode,
    builder: (_, __) => MaterialApp(
      title: 'Habits',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: mode.value,
      home: const Home(),
    ),
  ));
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  List<Habit> hs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('habits');
    final list = raw == null
        ? <Habit>[]
        : (jsonDecode(raw) as List).map((e) => Habit.fromJson(e)).toList();
    final t = today();
    for (final h in list) {
      if (h.date != t) {
        h.done = 0; // progres direset tiap hari
        h.date = t;
      }
    }
    setState(() => hs = list);
  }

  Future<void> _save({bool re = true}) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('habits', jsonEncode(hs.map((h) => h.toJson()).toList()));
    if (re) await reschedule(hs);
  }

  Future<void> _add() async {
    final h = await showModalBottomSheet<Habit>(
        context: context, isScrollControlled: true, builder: (_) => const AddSheet());
    if (h != null) {
      h.date = today();
      setState(() => hs.add(h));
      _save();
    }
  }

  void _settings() => showModalBottomSheet(
        context: context,
        builder: (_) => ListenableBuilder(
          listenable: Listenable.merge([lang, mode]),
          builder: (c, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('lang')),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'id', label: Text('Indonesia')),
                      ButtonSegment(value: 'en', label: Text('English')),
                    ],
                    selected: {lang.value},
                    onSelectionChanged: (s) {
                      lang.value = s.first;
                      saveSettings();
                      reschedule(hs); // perbarui teks notifikasi
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(tr('theme')),
                  const SizedBox(height: 8),
                  SegmentedButton<ThemeMode>(
                    segments: [
                      ButtonSegment(value: ThemeMode.system, label: Text(tr('system'))),
                      ButtonSegment(value: ThemeMode.light, label: Text(tr('light'))),
                      ButtonSegment(value: ThemeMode.dark, label: Text(tr('dark'))),
                    ],
                    selected: {mode.value},
                    onSelectionChanged: (s) {
                      mode.value = s.first;
                      saveSettings();
                    },
                  ),
                ]),
          ),
        ),
      );

  Widget _card(int i) {
    final h = hs[i];
    final ok = h.done >= h.target;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(h.name, style: Theme.of(context).textTheme.titleMedium)),
            IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  setState(() => hs.removeAt(i));
                  _save();
                }),
          ]),
          LinearProgressIndicator(value: (h.done / h.target).clamp(0.0, 1.0).toDouble()),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text('${h.done} / ${h.target} ${h.unit}${ok ? '  ✓' : ''}')),
            FilledButton(
                onPressed: () {
                  setState(() => h.done += h.step);
                  _save(re: false);
                },
                child: Text('+${h.step} ${h.unit}')),
          ]),
          const SizedBox(height: 4),
          Text('${tr('remind')}: ${h.times.join(', ')}',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: lang,
        builder: (context, _) => Scaffold(
          appBar: AppBar(title: Text(tr('title')), actions: [
            IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: tr('settings'),
                onPressed: _settings),
          ]),
          floatingActionButton: FloatingActionButton.extended(
              onPressed: _add, icon: const Icon(Icons.add), label: Text(tr('add'))),
          body: hs.isEmpty
              ? Center(child: Text(tr('empty'), textAlign: TextAlign.center))
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [for (var i = 0; i < hs.length; i++) _card(i)]),
        ),
      );
}

class AddSheet extends StatefulWidget {
  const AddSheet({super.key});
  @override
  State<AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<AddSheet> {
  final n = TextEditingController();
  final t = TextEditingController(text: '1');
  final u = TextEditingController(text: tr('times'));
  final s = TextEditingController(text: '1');
  TimeOfDay time = const TimeOfDay(hour: 8, minute: 0);

  @override
  Widget build(BuildContext c) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(c).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('tpl')),
                Wrap(spacing: 8, children: [
                  for (final h in templates())
                    ActionChip(label: Text(h.name), onPressed: () => Navigator.pop(c, h)),
                ]),
                const Divider(height: 32),
                Text(tr('custom')),
                TextField(controller: n, decoration: InputDecoration(labelText: tr('name'))),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: t,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: tr('target')))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: TextField(
                          controller: u,
                          decoration: InputDecoration(labelText: tr('unit')))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: TextField(
                          controller: s,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: tr('step')))),
                ]),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                    icon: const Icon(Icons.alarm),
                    label: Text('${tr('remind')} ${time.format(c)}'),
                    onPressed: () async {
                      final p = await showTimePicker(context: c, initialTime: time);
                      if (p != null) setState(() => time = p);
                    }),
                const SizedBox(height: 8),
                FilledButton(
                    onPressed: () {
                      final tg = int.tryParse(t.text) ?? 0, st = int.tryParse(s.text) ?? 1;
                      if (n.text.trim().isEmpty || tg <= 0) return;
                      final hm =
                          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                      Navigator.pop(c,
                          Habit(n.text.trim(), u.text.trim(), tg, st < 1 ? 1 : st, [hm], allDays));
                    },
                    child: Text(tr('save'))),
              ]),
        ),
      );
}
