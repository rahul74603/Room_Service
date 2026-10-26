import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../app_version.dart';
import '../data/database_helper.dart';
import '../data/settings_service.dart';
import '../utils/helpers.dart';
import '../utils/voice_parser.dart';
import '../utils/washing_helper.dart';
import 'chest_detail_screen.dart';
import 'history_screen.dart';
import 'menu_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final SpeechToText _speechToText = SpeechToText();
  bool _isListening = false;
  bool _speechReady = false;
  String _liveWords = '';

  List<Map<String, dynamic>> _chests = [];
  List<Map<String, dynamic>> _notes = [];
  Map<int, int> _roomDues = {}; // room number -> lena (expense - paid)
  Map<int, int> _washingPending = {}; // Sir id -> beete mahino ki pending dhulai
  Map<String, int> _totals = const {
    'totalDue': 0,
    'todayExpense': 0,
    'todayPaid': 0,
  };
  bool _isLoading = true;
  String? _loadError; // load fail ho to infinite spinner ki jagah error+retry

  final List<Color> _cardColors = const [
    Color(0xFF6C5CE7), Color(0xFF00B894),
    Color(0xFFE17055), Color(0xFF0984E3),
    Color(0xFFFD79A8), Color(0xFFFDCB6E),
  ];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// Startup par pehle DATA load karo, speech baad me — kuch phones par
  /// speech service judne me der lagti hai, usse home ki loading na atke.
  Future<void> _bootstrap() async {
    await _refreshAll();
    _initSpeech();
  }

  @override
  void dispose() {
    _speechToText.stop();
    super.dispose();
  }

  void _showMsg(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  // ---------- Speech ----------
  Future<void> _initSpeech() async {
    try {
      final available = await _speechToText.initialize(
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'done' || status == 'notListening') {
            setState(() => _isListening = false);
          }
        },
        onError: (error) {
          if (!mounted) return;
          setState(() => _isListening = false);
        },
      );
      if (!mounted) return;
      setState(() => _speechReady = available);
    } catch (_) {
      if (!mounted) return;
      setState(() => _speechReady = false);
    }
  }

  Future<String> _pickLocaleId() async {
    try {
      final locales = await _speechToText.locales();
      for (final l in locales) {
        final id = l.localeId.toLowerCase();
        if (id.startsWith('en_in') || id.startsWith('en-in')) return l.localeId;
      }
      final sys = await _speechToText.systemLocale();
      if (sys != null) return sys.localeId;
    } catch (_) {
      // neeche default use hoga
    }
    return 'en_IN';
  }

  Future<void> _startListening() async {
    // Pehle mic permission — pehle bina permission ke mic chupchaap fail ho jata tha
    final status = await Permission.microphone.request();
    if (!mounted) return;
    if (!status.isGranted) {
      _showMsg('Mic permission chahiye — Settings me jaake allow karo 🎙️',
          isError: true);
      return;
    }
    if (!_speechReady) {
      await _initSpeech();
      if (!mounted) return;
      if (!_speechReady) {
        _showMsg('Is phone me voice typing available nahi hai', isError: true);
        return;
      }
    }
    final localeId = await _pickLocaleId();
    if (!mounted) return;
    setState(() {
      _liveWords = '';
      _isListening = true;
    });
    await _speechToText.listen(
      onResult: (result) {
        if (!mounted) return;
        setState(() => _liveWords = result.recognizedWords);
        if (result.finalResult) {
          setState(() => _isListening = false);
          _processSmartVoice(result.recognizedWords);
        }
      },
      localeId: localeId,
      listenFor: const Duration(seconds: 15),
      listenOptions: SpeechListenOptions(
        cancelOnError: false,
        partialResults: true, // bolte waqt live text dikhega
      ),
    );
  }

  Future<void> _stopListening() async {
    await _speechToText.stop();
    if (!mounted) return;
    setState(() => _isListening = false);
  }

  // ---------- Data ----------
  Future<void> _refreshAll() async {
    try {
      final chests = await DatabaseHelper.instance.getAllChests();
      final notes = await DatabaseHelper.instance.getPendingNotes();
      final balanceRows = await DatabaseHelper.instance.getRoomBalances();
      final totals = await DatabaseHelper.instance.getDashboardTotals();
      final allWashingBilled =
          await DatabaseHelper.instance.getAllWashingBilled();
      final appSettings = await SettingsService.load();
      if (!mounted) return;
      final dues = <int, int>{};
      for (final row in balanceRows) {
        final no = (row['chest_no'] as num?)?.toInt() ?? 0;
        final expense = (row['expense'] as num?)?.toInt() ?? 0;
        final paid = (row['paid'] as num?)?.toInt() ?? 0;
        dues[no] = expense - paid;
      }
      // Ek room ke dono Sir paas-paas dikhen: pehle Room No., fir Chest No.
      int numKey(Object? v) {
        final m = RegExp(r'\d+').firstMatch(v?.toString() ?? '');
        return m == null ? 1 << 30 : int.parse(m.group(0)!);
      }

      // Database se mili list ki COPY par sort karo — asli list read-only
      // ho sakti hai (sqflite), usey seedha sort karne par app atki thi.
      final sortedChests = [...chests]..sort((a, b) {
        var c = numKey(a['room_no']).compareTo(numKey(b['room_no']));
        if (c != 0) return c;
        c = (a['room_no']?.toString() ?? '')
            .compareTo(b['room_no']?.toString() ?? '');
        if (c != 0) return c;
        c = numKey(a['chest_no']).compareTo(numKey(b['chest_no']));
        if (c != 0) return c;
        return ((a['number'] as num?)?.toInt() ?? 0)
            .compareTo((b['number'] as num?)?.toInt() ?? 0);
      });
      // Dhulai pending (beete hue mahino ka unbilled) har Sir ke liye
      final washingPending = <int, int>{};
      final today = DateTime.now();
      for (final chest in chests) {
        if (((chest['is_washing_on'] as num?)?.toInt() ?? 0) != 1) continue;
        final start =
            WashingHelper.parseServiceDate(chest['washing_start_date']);
        if (start == null) continue;
        final sirId = (chest['number'] as num?)?.toInt() ?? 0;
        final months = WashingHelper.buildMonths(
          serviceStart: start,
          today: today,
          dailyRate: appSettings.washingDailyRate,
          monthlyAmount: appSettings.washingMonthlyAmount,
          billedByMonth: allWashingBilled[sirId] ?? const {},
        );
        final pending = WashingHelper.pastPendingTotal(months);
        if (pending > 0) washingPending[sirId] = pending;
      }
      setState(() {
        _chests = sortedChests;
        _notes = notes;
        _roomDues = dues;
        _washingPending = washingPending;
        _totals = totals;
        _loadError = null;
        _isLoading = false;
      });
    } catch (e) {
      // Kabhi infinite loading par mat atko — error dikhao, Retry do
      if (!mounted) return;
      setState(() {
        _loadError = '$e';
        _isLoading = false;
      });
    }
  }

  Widget _buildLoadErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            const Text(
              'Data load nahi ho paya',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SelectableText(
              _loadError ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                setState(() => _isLoading = true);
                _refreshAll();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Dobara Try Karo'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openChest(Map<String, dynamic> chest) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ChestDetailScreen(chestData: chest)),
    );
    _refreshAll(); // wapas aane par balance turant update
  }

  // ---------- Photo (ab photo app ke folder me copy hoti hai, gayab nahi hogi) ----------
  Future<void> _showImageSourceSheet(int chestNumber) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery se photo lo'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera se photo lo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _pickAndSaveImage(chestNumber, source);
  }

  Future<void> _pickAndSaveImage(int chestNumber, ImageSource source) async {
    try {
      final picked = await ImagePicker()
          .pickImage(source: source, imageQuality: 80, maxWidth: 1024);
      if (picked == null) return;
      final docs = await getApplicationDocumentsDirectory();
      final imgDir = Directory('${docs.path}/room_images');
      if (!await imgDir.exists()) await imgDir.create(recursive: true);
      final ext = picked.path.contains('.')
          ? picked.path.substring(picked.path.lastIndexOf('.'))
          : '.jpg';
      final destPath =
          '${imgDir.path}/room_${chestNumber}_${DateTime.now().millisecondsSinceEpoch}$ext';
      await File(picked.path).copy(destPath);
      await DatabaseHelper.instance.updateChestImage(chestNumber, destPath);
      if (!mounted) return;
      _refreshAll();
      _showMsg('Photo Updated! 📸');
    } catch (e) {
      _showMsg('Photo load nahi ho payi: $e', isError: true);
    }
  }

  // ---------- CSV Report ----------
  Future<void> _exportFullReport() async {
    try {
      final allData =
          await DatabaseHelper.instance.getAllTransactionsForReport();
      if (allData.isEmpty) {
        _showMsg('Report ke liye abhi koi data nahi hai', isError: true);
        return;
      }
      final buffer =
          StringBuffer('Date,Sir Name,Room No,Chest No,Item,Type,Amount\n');
      for (final row in allData) {
        buffer.writeln([
          AppHelpers.csvEscape(AppHelpers.formatDateTime(row['date'] as String?)),
          AppHelpers.csvEscape(row['name'] ?? 'Sir ${row['chest_no']}'),
          AppHelpers.csvEscape(row['room_no'] ?? ''),
          AppHelpers.csvEscape(row['chest_display'] ?? row['chest_no']),
          AppHelpers.csvEscape(row['title']),
          row['is_advance'] == 1 ? 'Jama (Paid)' : 'Kharcha',
          AppHelpers.csvEscape(row['amount']),
        ].join(','));
      }
      final dir = await getApplicationDocumentsDirectory();
      final path =
          '${dir.path}/Hotel_Report_${DateTime.now().millisecondsSinceEpoch}.csv';
      await File(path).writeAsString(buffer.toString());
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path)], text: 'Hotel Report (CSV)'),
      );
    } catch (e) {
      _showMsg('Error: $e', isError: true);
    }
  }

  // ---------- Voice processing ----------
  static String _personSubline(Map<String, dynamic> p) {
    final room = p['room_no']?.toString() ?? '';
    final chest = p['chest_no']?.toString() ?? '';
    return [
      if (room.isNotEmpty) 'Room $room',
      if (chest.isNotEmpty) 'Chest $chest',
    ].join(' • ');
  }

  /// Boli gayi pehchan (chest/room) se Sir ki list nikalo.
  /// Chest No. sabse pakka — sirf Room No. bola ho aur 2 Sir hon to
  /// do naam aayenge, user chunega.
  List<Map<String, dynamic>> _resolvePersons(int? chestNo, int? roomNo) {
    bool matchNo(Object? v, int n) =>
        v != null && int.tryParse(v.toString().trim()) == n;
    if (chestNo != null) {
      final byChest =
          _chests.where((c) => matchNo(c['chest_no'], chestNo)).toList();
      if (byChest.isNotEmpty) return byChest;
    }
    if (roomNo != null) {
      final byRoom =
          _chests.where((c) => matchNo(c['room_no'], roomNo)).toList();
      if (byRoom.isNotEmpty) return byRoom;
    }
    // Purani aadat wala fallback: jo number bola, use ID/chest/room kahi bhi dhundo
    final anyNo = chestNo ?? roomNo;
    if (anyNo != null) {
      return _chests
          .where((c) =>
              matchNo(c['number'], anyNo) ||
              matchNo(c['chest_no'], anyNo) ||
              matchNo(c['room_no'], anyNo))
          .toList();
    }
    return [];
  }

  Future<Map<String, dynamic>?> _choosePerson(
      List<Map<String, dynamic>> persons) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Kis Sir ke khate me?',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ...persons.map(
              (p) => ListTile(
                leading: const Icon(Icons.person),
                title: Text(p['name']?.toString() ?? 'Sir'),
                subtitle: Text(_personSubline(p)),
                onTap: () => Navigator.pop(ctx, p),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _processSmartVoice(String text) async {
    if (text.trim().isEmpty) return;
    final result = VoiceParser.parseRequest(text);
    final int? chestNo = result['chestNumber'] as int?;
    final int? roomNo = result['roomNumber'] as int?;

    if (chestNo == null && roomNo == null) {
      await DatabaseHelper.instance.addNote(text.trim());
      _refreshAll();
      _showMsg('Sir ki pehchan samajh nahi aayi — Note save kar diya 📝');
      return;
    }

    final matches = _resolvePersons(chestNo, roomNo);
    if (matches.isEmpty) {
      await DatabaseHelper.instance.addNote(text.trim());
      _refreshAll();
      _showMsg(
          'Chest ${chestNo ?? ''} / Room ${roomNo ?? ''} wala koi Sir nahi mila — Note save kar diya 📝',
          isError: true);
      return;
    }

    var person = matches.first;
    if (matches.length > 1) {
      final chosen = await _choosePerson(matches);
      if (chosen == null) return; // user ne cancel kiya
      person = chosen;
    }

    _showVoiceConfirmDialog(
      person,
      result['title'] as String,
      (result['amount'] as int?) ?? 0,
      (result['quantity'] as int?) ?? 1,
      (result['isPaymentHint'] as bool?) ?? false,
    );
  }

  Future<void> _showVoiceConfirmDialog(Map<String, dynamic> person,
      String item, int amount, int quantity, bool isPaymentHint) async {
    final chestNo = (person['number'] as num).toInt();
    final personName = person['name']?.toString() ?? 'Sir';
    final personSubline = _personSubline(person);
    final i = TextEditingController(text: item);
    final p = TextEditingController(text: amount == 0 ? '' : '$amount');
    final q = TextEditingController(text: '$quantity');
    var isPayment = isPaymentHint;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            '$personName${personSubline.isEmpty ? '' : ' ($personSubline)'} — ${isPayment ? 'JAMA' : 'KHARCHA'}',
            style: TextStyle(
              color: isPayment ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => setDialogState(() => isPayment = false),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        color: !isPayment ? Colors.red : Colors.grey[200],
                        child: Center(
                          child: Text('Kharcha',
                              style: TextStyle(
                                  color:
                                      !isPayment ? Colors.white : Colors.black)),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () => setDialogState(() => isPayment = true),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        color: isPayment ? Colors.green : Colors.grey[200],
                        child: Center(
                          child: Text('Jama',
                              style: TextStyle(
                                  color:
                                      isPayment ? Colors.white : Colors.black)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              TextField(
                controller: i,
                decoration: InputDecoration(
                  labelText: isPayment ? 'Note (e.g. Advance)' : 'Item Name',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: p,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: isPayment ? 'Amount' : 'Price (Per Item)',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  if (!isPayment) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: q,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Quantity',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('CANCEL', style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isPayment ? Colors.green : Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final price = int.tryParse(p.text.trim()) ?? 0;
                final qty = int.tryParse(q.text.trim()) ?? 1;
                if (price <= 0) {
                  _showMsg('Sahi amount daalo (0 se bada)', isError: true);
                  return;
                }
                if (qty <= 0) {
                  _showMsg('Quantity kam se kam 1 rakho', isError: true);
                  return;
                }
                final total = isPayment ? price : price * qty;
                var title = i.text.trim();
                if (title.isEmpty) {
                  title = isPayment ? 'Payment/Advance' : 'General Item';
                } else if (!isPayment && qty > 1) {
                  title = '$title (x$qty)';
                }
                await DatabaseHelper.instance
                    .addTransaction(chestNo, title, total, isPayment);
                if (!dialogCtx.mounted) return;
                Navigator.pop(dialogCtx);
                _refreshAll();
                _showMsg('Saved! ${AppHelpers.formatRupees(total)} ✅');
              },
              child: const Text('SAVE'),
            ),
          ],
        ),
      ),
    );
    i.dispose();
    p.dispose();
    q.dispose();
  }

  // ---------- Room edit ----------
  Future<void> _showEditChestDialog(Map<String, dynamic> chest) async {
    final number = (chest['number'] as num).toInt();
    final n = TextEditingController(text: chest['name']?.toString() ?? '');
    final chestC =
        TextEditingController(text: chest['chest_no']?.toString() ?? '');
    final roomC =
        TextEditingController(text: chest['room_no']?.toString() ?? '');
    final p = TextEditingController(text: chest['phone']?.toString() ?? '');
    final hasPhoto =
        (chest['image_path'] as String?)?.isNotEmpty ?? false;

    await showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('${chest['name']?.toString() ?? 'Sir'} — Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: n,
                decoration: const InputDecoration(labelText: 'Sir ka naam')),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: chestC,
                    decoration:
                        const InputDecoration(labelText: 'Chest No.'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: roomC,
                    decoration: const InputDecoration(labelText: 'Room No.'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: p,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(dialogCtx);
                    _showImageSourceSheet(number);
                  },
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Photo'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white),
                ),
                if (hasPhoto) ...[
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: () async {
                      await DatabaseHelper.instance
                          .updateChestImage(number, null);
                      if (!dialogCtx.mounted) return;
                      Navigator.pop(dialogCtx);
                      _refreshAll();
                    },
                    child: const Text('Photo Hatao'),
                  ),
                ],
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              _confirmDeleteChest(chest);
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () async {
              var name = n.text.trim();
              if (name.isEmpty) name = 'Sir $number';
              final newChestNo = chestC.text.trim();
              // Chest number kisi aur Sir ka ho to roko (galti se hisaab mix na ho)
              if (newChestNo.isNotEmpty &&
                  await DatabaseHelper.instance
                      .isChestNoTaken(newChestNo, excludingId: number)) {
                _showMsg(
                    'Chest No. $newChestNo pehle se kisi aur Sir ka hai!',
                    isError: true);
                return;
              }
              await DatabaseHelper.instance.updateChestDetails(
                number,
                name,
                p.text.trim(),
                chestNo: newChestNo,
                roomNo: roomC.text.trim(),
              );
              if (!dialogCtx.mounted) return;
              Navigator.pop(dialogCtx);
              _refreshAll();
              _showMsg('Sir details update ho gayi ✅');
            },
            child: const Text('UPDATE'),
          ),
        ],
      ),
    );
    n.dispose();
    chestC.dispose();
    roomC.dispose();
    p.dispose();
  }

  Future<void> _confirmDeleteChest(Map<String, dynamic> chest) async {
    final number = (chest['number'] as num).toInt();
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('${chest['name']?.toString() ?? 'Sir'} ko hatayein?'),
            content: const Text(
                'Is Sir ka saara hisaab bhi delete ho jayega. Ye wapas nahi aayega! (Sir sirf badle hain to pehle Checkout karke naam badalna behtar hai.)'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('NAHI')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('HAAN, DELETE'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await DatabaseHelper.instance.deleteChest(number);
    _refreshAll();
    _showMsg('${chest['name']?.toString() ?? 'Sir'} hata diye gaye');
  }

  // ---------- Notes ----------
  Future<void> _addNoteDialog() async {
    final c = TextEditingController();
    await showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Naya Note 📝'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Note', hintText: 'e.g. Room 2 me towel bhejna hai'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
              if (c.text.trim().isEmpty) return;
              await DatabaseHelper.instance.addNote(c.text.trim());
              if (!dialogCtx.mounted) return;
              Navigator.pop(dialogCtx);
              _refreshAll();
            },
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
    c.dispose();
  }

  Future<void> _noteDone(Map<String, dynamic> note) async {
    final id = (note['id'] as num).toInt();
    final content = note['content']?.toString() ?? '';
    await DatabaseHelper.instance.markNoteDone(id);
    _refreshAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Note done ✅'),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () async {
            await DatabaseHelper.instance.addNote(content);
            _refreshAll();
          },
        ),
      ),
    );
  }

  Future<void> _noteOptions(Map<String, dynamic> note) async {
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: const Text('Done Karo'),
              onTap: () {
                Navigator.pop(ctx);
                _noteDone(note);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete Karo'),
              onTap: () async {
                Navigator.pop(ctx);
                await DatabaseHelper.instance
                    .deleteNote((note['id'] as num).toInt());
                _refreshAll();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Build ----------
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'RoomService Pro',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            Text(
              'Version $appVersion',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
          ],
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (context) => const MenuScreen()));
              _refreshAll();
            },
            icon: Icon(Icons.restaurant_menu,
                color: isDark ? Colors.white : Colors.black),
            tooltip: 'Menu',
          ),
          IconButton(
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (context) => const HistoryScreen()));
              _refreshAll();
            },
            icon: Icon(Icons.history,
                color: isDark ? Colors.white : Colors.black),
            tooltip: 'Checkout History',
          ),
          IconButton(
            onPressed: _exportFullReport,
            icon: Icon(Icons.analytics,
                color: isDark ? Colors.white : Colors.black),
            tooltip: 'Export Report (CSV)',
          ),
          IconButton(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const SettingsScreen()),
              );
              _refreshAll();
            },
            icon: Icon(Icons.settings,
                color: isDark ? Colors.white : Colors.black),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (_loadError != null && _chests.isEmpty)
              ? _buildLoadErrorState()
              : Column(
              children: [
                _buildSummaryCard(isDark),
                _buildNotesStrip(isDark),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refreshAll,
                    child: GridView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 5, 16, 100),
                      itemCount: _chests.length + 1,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.9,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      itemBuilder: (context, index) {
                        if (index == _chests.length) {
                          return _buildAddButton(isDark);
                        }
                        final themeColor =
                            _cardColors[index % _cardColors.length];
                        return _buildChestCard(_chests[index], themeColor);
                      },
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isListening)
            Container(
              constraints: const BoxConstraints(maxWidth: 300),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.black87,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _liveWords.isEmpty
                    ? '🎙️ Sun raha hoon... boliye'
                    : _liveWords,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          GestureDetector(
            onTap: () => _isListening ? _stopListening() : _startListening(),
            child: Container(
              height: 70,
              width: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isListening
                    ? Colors.red
                    : (isDark ? Colors.white : Colors.black),
                boxShadow: [
                  BoxShadow(
                    color: _isListening
                        ? Colors.red.withValues(alpha: 0.4)
                        : Colors.black.withValues(alpha: 0.2),
                    blurRadius: 15,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(
                _isListening ? Icons.mic : Icons.mic_none,
                color: _isListening
                    ? Colors.white
                    : (isDark ? Colors.black : Colors.white),
                size: 30,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(bool isDark) {
    final totalDue = _totals['totalDue'] ?? 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 5)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Total Lena (Sab Sir)',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              Text(
                AppHelpers.formatRupees(totalDue),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: totalDue > 0 ? Colors.red : Colors.green,
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Aaj Kharcha ${AppHelpers.formatRupees(_totals['todayExpense'] ?? 0)}',
                style: const TextStyle(fontSize: 12, color: Colors.red),
              ),
              Text(
                'Aaj Jama ${AppHelpers.formatRupees(_totals['todayPaid'] ?? 0)}',
                style: const TextStyle(fontSize: 12, color: Colors.green),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNotesStrip(bool isDark) {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: ActionChip(
              avatar: const Icon(Icons.note_add, size: 16),
              label: const Text('Note'),
              onPressed: _addNoteDialog,
            ),
          ),
          ..._notes.map(
            (note) => GestureDetector(
              onTap: () => _noteOptions(note),
              child: Container(
                margin: const EdgeInsets.only(right: 10, bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[800] : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.circle, color: Colors.orange, size: 10),
                    const SizedBox(width: 8),
                    Text(
                      note['content']?.toString() ?? '',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => _noteDone(note),
                      child: const Icon(Icons.check_circle,
                          color: Colors.green, size: 18),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChestCard(Map<String, dynamic> chest, Color themeColor) {
    final number = (chest['number'] as num).toInt();
    final sirName = chest['name']?.toString() ?? 'Sir';
    final chestDisplay = (chest['chest_no']?.toString().isNotEmpty ?? false)
        ? chest['chest_no'].toString()
        : '$number';
    final roomDisplay = chest['room_no']?.toString() ?? '';
    final washingPendingAmt = _washingPending[number] ?? 0;
    final washingOn = chest['is_washing_on'] == 1;
    final String? imagePath = chest['image_path'] as String?;
    final imageFile = (imagePath != null && imagePath.isNotEmpty)
        ? File(imagePath)
        : null;
    final hasImage = imageFile != null && imageFile.existsSync();
    final due = _roomDues[number] ?? 0;

    return InkWell(
      onTap: () => _openChest(chest),
      onLongPress: () => _showEditChestDialog(chest),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: hasImage
              ? null
              : LinearGradient(
                  colors: [themeColor, themeColor.withValues(alpha: 0.8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          image: hasImage
              ? DecorationImage(image: FileImage(imageFile), fit: BoxFit.cover)
              : null,
          boxShadow: [
            BoxShadow(
              color: themeColor.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            if (hasImage)
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: Colors.black45,
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: hasImage
                              ? Colors.white30
                              : Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.person,
                            color: Colors.white, size: 20),
                      ),
                      GestureDetector(
                        onTap: () => _showEditChestDialog(chest),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: const BoxDecoration(
                            color: Colors.black26,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.settings,
                              color: Colors.white, size: 16),
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Chest Number sabse bada — door se ek nazar me pehchan
                      const Text(
                        'CHEST NO.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          chestDisplay,
                          maxLines: 1,
                          style: GoogleFonts.poppins(
                            fontSize: 40,
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            height: 1.0,
                          ),
                        ),
                      ),
                      Text(
                        sirName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          height: 1.1,
                        ),
                      ),
                      if (roomDisplay.isNotEmpty)
                        Text(
                          '🚪 Room $roomDisplay',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.white70,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      if (washingOn) ...[
                        const SizedBox(height: 4),
                        if (washingPendingAmt > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red.shade700,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.local_laundry_service,
                                    color: Colors.white, size: 12),
                                const SizedBox(width: 4),
                                Text(
                                  'Dhulai Pending ${AppHelpers.formatRupees(washingPendingAmt)}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          )
                        else
                          const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.local_laundry_service,
                                  color: Colors.white, size: 13),
                              SizedBox(width: 4),
                              Text(
                                'Dhulai ON',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                      ],
                      if (due != 0) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: due > 0 ? Colors.red : Colors.green,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            due > 0
                                ? 'Lena ${AppHelpers.formatRupees(due)}'
                                : 'Advance ${AppHelpers.formatRupees(due.abs())}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddButton(bool isDark) {
    return InkWell(
      onTap: _showAddChestDialog,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: isDark ? Colors.grey[800] : Colors.white,
          border: Border.all(color: Colors.grey.shade300, width: 2),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_add, size: 40, color: Colors.grey),
              Text('Sir Add Karo',
                  style:
                      TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddChestDialog() async {
    final nameC = TextEditingController();
    final chestC = TextEditingController();
    final roomC = TextEditingController();
    final phoneC = TextEditingController();
    await showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Naye Sir Add Karo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameC,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Sir ka naam *'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: chestC,
                    decoration:
                        const InputDecoration(labelText: 'Chest No. *'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: roomC,
                    decoration: const InputDecoration(labelText: 'Room No.'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phoneC,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
              final name = nameC.text.trim();
              final chestNo = chestC.text.trim();
              if (name.isEmpty) {
                _showMsg('Sir ka naam daalo', isError: true);
                return;
              }
              if (chestNo.isEmpty) {
                _showMsg('Chest No. daalo (yehi pakki pehchan hai)',
                    isError: true);
                return;
              }
              final newId = await DatabaseHelper.instance.addPerson(
                name: name,
                chestNo: chestNo,
                roomNo: roomC.text.trim(),
                phone: phoneC.text.trim(),
              );
              if (!dialogCtx.mounted) return;
              Navigator.pop(dialogCtx);
              if (newId != null) {
                _refreshAll();
                _showMsg('$name add ho gaye ✅');
              } else {
                _showMsg('Chest No. $chestNo pehle se kisi Sir ka hai!',
                    isError: true);
              }
            },
            child: const Text('ADD'),
          ),
        ],
      ),
    );
    nameC.dispose();
    chestC.dispose();
    roomC.dispose();
    phoneC.dispose();
  }
}
