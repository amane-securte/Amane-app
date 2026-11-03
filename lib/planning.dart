import 'package:flutter/material.dart';

import 'data.dart';
import 'i18n.dart';
import 'theme.dart';
import 'widgets.dart';

String ymd(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
DateTime parseYmd(String s) => DateTime.tryParse(s) ?? DateTime.now();
DateTime weekStart(DateTime d) =>
    DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

class ShiftDoc {
  ShiftDoc(this.id, Map<String, dynamic> m)
      : uid = m['uid'] is String ? m['uid'] as String : '',
        name = m['name'] is String ? m['name'] as String : '',
        siteId = m['siteId'] is String ? m['siteId'] as String : '',
        siteName = m['siteName'] is String ? m['siteName'] as String : '',
        date = m['date'] is String ? m['date'] as String : '',
        start = m['start'] is String ? m['start'] as String : '07:00',
        end = m['end'] is String ? m['end'] as String : '19:00';
  final String id, uid, name, siteId, siteName, date, start, end;

  bool get overnight => end.compareTo(start) <= 0;
}

/// Mois en toutes lettres, sans dépendre d'un paquet de dates.
String dayLabel(T t, DateTime d) {
  const ar = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
  const fr = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];
  final w = (t.lang == 'ar' ? ar : fr)[d.weekday - 1];
  return '$w ${dm(d)}';
}

/// Onglet « Planning » de l'administrateur.
class PlanningTab extends StatefulWidget {
  const PlanningTab(
      {super.key, required this.t, required this.guards, required this.sites});
  final T t;
  final List<UserDoc> guards;
  final List<Site> sites;

  @override
  State<PlanningTab> createState() => _PlanningTabState();
}

class _PlanningTabState extends State<PlanningTab> {
  late DateTime _week = weekStart(DateTime.now());
  late Stream<QueryMap> _stream = _query();

  T get t => widget.t;

  Stream<QueryMap> _query() => db
      .collection('shifts')
      .where('date', isGreaterThanOrEqualTo: ymd(_week))
      .where('date', isLessThanOrEqualTo: ymd(_week.add(const Duration(days: 6))))
      .snapshots();

  void _move(int days) => setState(() {
        _week = days == 0
            ? weekStart(DateTime.now())
            : _week.add(Duration(days: days));
        _stream = _query();
      });

  @override
  Widget build(BuildContext context) {
    final today = ymd(DateTime.now());
    return StreamBuilder<QueryMap>(
      stream: _stream,
      builder: (context, snap) {
        final shifts = (snap.data?.docs ?? const [])
            .map((d) => ShiftDoc(d.id, d.data()))
            .toList()
          ..sort((a, b) => '${a.date}${a.start}'.compareTo('${b.date}${b.start}'));
        return Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                Row(
                  children: [
                    IconButton(
                        onPressed: () => _move(-7),
                        icon: const Icon(Icons.chevron_left)),
                    Expanded(
                      child: TextButton(
                        onPressed: () => _move(0),
                        child: Text(
                            '${dm(_week)} – ${dm(_week.add(const Duration(days: 6)))}',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    IconButton(
                        onPressed: () => _move(7),
                        icon: const Icon(Icons.chevron_right)),
                  ],
                ),
                for (var i = 0; i < 7; i++)
                  _day(_week.add(Duration(days: i)), shifts, today),
              ],
            ),
            PositionedDirectional(
              end: 16,
              bottom: 16,
              child: FloatingActionButton.extended(
                onPressed: () => _edit(null, DateTime.now()),
                icon: const Icon(Icons.add),
                label: Text(t('add_shift')),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _day(DateTime d, List<ShiftDoc> all, String today) {
    final key = ymd(d);
    final list = all.where((s) => s.date == key).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(dayLabel(t, d),
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: key == today ? gold : ink)),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add_circle_outline, size: 20),
                onPressed: () => _edit(null, d),
              ),
            ],
          ),
          if (list.isEmpty)
            Text(t('no_shift'), style: const TextStyle(color: muted, fontSize: 13))
          else
            ...list.map((s) => Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    dense: true,
                    leading: ltrText('${s.start}–${s.end}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    title: Text(s.name),
                    subtitle: Text(
                        s.siteName + (s.overnight ? ' · ${t('overnight')}' : '')),
                    onTap: () => _edit(s, parseYmd(s.date)),
                  ),
                )),
        ],
      ),
    );
  }

  Future<void> _edit(ShiftDoc? s, DateTime day) async {
    final guards = widget.guards.where((g) => g.role == 'guard').toList();
    if (guards.isEmpty || widget.sites.isEmpty) {
      snack(context, t('pick_first'), color: warn);
      return;
    }
    var date = s == null ? day : parseYmd(s.date);
    var guardId = s?.uid ?? guards.first.id;
    String siteOf(String gid) =>
        guards.where((g) => g.id == gid).firstOrNull?.siteId ??
        widget.sites.first.id;
    var siteId = s?.siteId.isNotEmpty == true ? s!.siteId : siteOf(guardId);
    if (!widget.sites.any((x) => x.id == siteId)) siteId = widget.sites.first.id;
    var start = s?.start ?? '07:00', end = s?.end ?? '19:00';

    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(s == null ? t('add_shift') : t('edit_shift')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text(dayLabel(t, date)),
                  onPressed: () async {
                    final p = await showDatePicker(
                      context: ctx,
                      initialDate: date,
                      firstDate: DateTime.now().subtract(const Duration(days: 60)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (p != null) setD(() => date = p);
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: guardId,
                  decoration: InputDecoration(labelText: t('guard')),
                  items: [
                    for (final g in guards)
                      DropdownMenuItem(value: g.id, child: Text(g.name)),
                  ],
                  onChanged: (v) => setD(() {
                    guardId = v ?? guardId;
                    if (s == null) siteId = siteOf(guardId);
                  }),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: ValueKey(siteId),
                  initialValue: siteId,
                  decoration: InputDecoration(labelText: t('site')),
                  items: [
                    for (final x in widget.sites)
                      DropdownMenuItem(value: x.id, child: Text(x.name)),
                  ],
                  onChanged: (v) => setD(() => siteId = v ?? siteId),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(t('preset_day')),
                      selected: start == '07:00' && end == '19:00',
                      onSelected: (_) => setD(() {
                        start = '07:00';
                        end = '19:00';
                      }),
                    ),
                    ChoiceChip(
                      label: Text(t('preset_night')),
                      selected: start == '19:00' && end == '07:00',
                      onSelected: (_) => setD(() {
                        start = '19:00';
                        end = '07:00';
                      }),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () async {
                          final p = await _pickTime(ctx, start);
                          if (p != null) setD(() => start = p);
                        },
                        child: Text('${t('start')} $start'),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () async {
                          final p = await _pickTime(ctx, end);
                          if (p != null) setD(() => end = p);
                        },
                        child: Text('${t('end')} $end'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            if (s != null)
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'delete'),
                child: Text(t('delete'), style: const TextStyle(color: danger)),
              ),
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, 'save'),
                child: Text(t('save'))),
          ],
        ),
      ),
    );

    if (res == 'delete' && s != null) {
      await db.collection('shifts').doc(s.id).delete();
      return;
    }
    if (res != 'save') return;
    final g = guards.firstWhere((x) => x.id == guardId);
    final site = widget.sites.firstWhere((x) => x.id == siteId);
    final data = {
      'uid': g.id,
      'name': g.name,
      'siteId': site.id,
      'siteName': site.name,
      'date': ymd(date),
      'start': start,
      'end': end,
    };
    if (s == null) {
      await db.collection('shifts').add(data);
    } else {
      await db.collection('shifts').doc(s.id).update(data);
    }
    if (mounted) {
      setState(() {
        _week = weekStart(date);
        _stream = _query();
      });
    }
  }

  Future<String?> _pickTime(BuildContext ctx, String cur) async {
    final parts = cur.split(':');
    final p = await showTimePicker(
      context: ctx,
      initialTime: TimeOfDay(
          hour: int.tryParse(parts.first) ?? 7,
          minute: int.tryParse(parts.last) ?? 0),
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    return p == null ? null : '${two(p.hour)}:${two(p.minute)}';
  }
}

/// Prochaines missions d'un agent (vue agent).
class MyShifts extends StatelessWidget {
  const MyShifts({super.key, required this.t, required this.stream});
  final T t;
  final Stream<QueryMap> stream;

  @override
  Widget build(BuildContext context) {
    final today = ymd(DateTime.now());
    return StreamBuilder<QueryMap>(
      stream: stream,
      builder: (context, snap) {
        final list = (snap.data?.docs ?? const [])
            .map((d) => ShiftDoc(d.id, d.data()))
            .where((s) => s.date.compareTo(today) >= 0)
            .toList()
          ..sort((a, b) => '${a.date}${a.start}'.compareTo('${b.date}${b.start}'));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('my_shifts'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (list.isEmpty)
              Text(t('no_upcoming'), style: const TextStyle(color: muted))
            else
              ...list.take(10).map((s) => Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      dense: true,
                      title: Text(dayLabel(t, parseYmd(s.date)),
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: s.date == today ? gold : ink)),
                      subtitle: Text(s.siteName),
                      trailing: ltrText('${s.start}–${s.end}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  )),
          ],
        );
      },
    );
  }
}
