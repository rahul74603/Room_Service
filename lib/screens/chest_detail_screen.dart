import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import 'package:printing/printing.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/database_helper.dart';
import '../data/settings_service.dart';
import '../utils/helpers.dart';
import '../utils/voice_parser.dart';
import '../utils/washing_helper.dart';

class ChestDetailScreen extends StatefulWidget {
  final Map<String, dynamic> chestData;
  const ChestDetailScreen({super.key, required this.chestData});

  @override
  State<ChestDetailScreen> createState() => _ChestDetailScreenState();
}

class _ChestDetailScreenState extends State<ChestDetailScreen> {
  final SpeechToText _speechToText = SpeechToText();
  bool _isListening = false;
  bool _speechReady = false;
  final FlutterTts _flutterTts = FlutterTts();
  bool _isSpeaking = false;

  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _menuItems = [];

  int _totalExpense = 0; // Kul Kharcha (Debit)
  int _totalPaid = 0; // Kul Jama (Credit)
  int _balanceDue = 0; // Baki/Lena

  bool _isLoading = true;
  bool _isWashingOn = false;
  String _washingStartDate = '';

  // Fresh name/phone DB se (pehle purana widget wala data use ho raha tha)
  late String _roomName;
  late String _phone;
  String _roomNo = '';
  String _chestDisplay = '';
  DateTime? _washingStart; // sirf date (time hamesha 00:00)
  AppSettings _settings = const AppSettings();
  List<WashingMonth> _washingMonths = const []; // mahine-daar dhulai status

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  int get _chestNo => (widget.chestData['number'] as num).toInt();

  @override
  void initState() {
    super.initState();
    _roomName = widget.chestData['name']?.toString() ?? 'Room $_chestNo';
    _phone = widget.chestData['phone']?.toString() ?? '';
    _refreshData();
    _initSpeech();
    _initTts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _speechToText.stop();
    _flutterTts.stop();
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

  Future<void> _initTts() async {
    try {
      await _flutterTts.setLanguage('hi-IN');
      await _flutterTts.setSpeechRate(0.45);
      await _flutterTts.setPitch(1.0);
      _flutterTts.setCompletionHandler(() {
        if (mounted) setState(() => _isSpeaking = false);
      });
      _flutterTts.setErrorHandler((msg) {
        if (mounted) setState(() => _isSpeaking = false);
      });
    } catch (_) {
      // TTS available na ho to chupchaap aage badho
    }
  }

  Future<void> _refreshData() async {
   try {
    final chest = await DatabaseHelper.instance.getChest(_chestNo);
    final data = await DatabaseHelper.instance.getTransactions(_chestNo);
    final menu = await DatabaseHelper.instance.getMenuItems();
    final appSettings = await SettingsService.load();
    final billedByMonth =
        await DatabaseHelper.instance.getWashingBilledByMonth(_chestNo);
    if (!mounted) return;

    if (chest == null) {
      // Room delete ho gaya hai — crash ki jagah shanti se wapas jao
      _showMsg('Ye room ab maujood nahi hai', isError: true);
      Navigator.pop(context);
      return;
    }

    var expense = 0;
    var paid = 0;
    for (final item in data) {
      final amt = (item['amount'] as num?)?.toInt() ?? 0;
      if (item['is_advance'] == 1) {
        paid += amt;
      } else {
        expense += amt;
      }
    }

    setState(() {
      _roomName = chest['name']?.toString() ?? _roomName;
      _phone = chest['phone']?.toString() ?? '';
      _roomNo = chest['room_no']?.toString() ?? '';
      _chestDisplay = chest['chest_no']?.toString() ?? '';
      _isWashingOn = chest['is_washing_on'] == 1;
      _washingStartDate = chest['washing_start_date']?.toString() ?? '';
      _washingStart = _parseWashingDate(_washingStartDate);
      _settings = appSettings;
      _washingMonths = _isWashingOn && _washingStart != null
          ? WashingHelper.buildMonths(
              serviceStart: _washingStart!,
              today: DateTime.now(),
              dailyRate: _settings.washingDailyRate,
              monthlyAmount: _settings.washingMonthlyAmount,
              billedByMonth: billedByMonth,
            )
          : const [];
      _transactions = data;
      _totalExpense = expense;
      _totalPaid = paid;
      _balanceDue = expense - paid;
      _menuItems = menu;
      _isLoading = false;
    });
   } catch (e) {
     // Infinite loading ki jagah error dikhao
     if (!mounted) return;
     setState(() => _isLoading = false);
     _showMsg('Data load error: $e', isError: true);
   }
  }

  List<Map<String, dynamic>> get _visibleTransactions {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _transactions;
    return _transactions
        .where((t) =>
            (t['title']?.toString().toLowerCase().contains(q) ?? false))
        .toList();
  }

  // ---------- Checkout (ab hisaab history me save hota hai) ----------
  Future<void> _checkoutRoom() async {
    if (_transactions.isEmpty) {
      _showMsg('Room pehle se khali hai — koi hisaab nahi hai');
      return;
    }
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Checkout / Clear Room?'),
        content: Text(
          'Total Bill: ${AppHelpers.formatRupees(_totalExpense)}\n'
          'Jama: ${AppHelpers.formatRupees(_totalPaid)}\n'
          'Baki (Lena): ${AppHelpers.formatRupees(_balanceDue)}\n\n'
          'Checkout par ye hisaab History me save ho jayega aur room khali ho jayega.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('CANCEL')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'whatsapp'),
              child: const Text('WHATSAPP BILL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, 'checkout'),
            child: const Text('CHECKOUT'),
          ),
        ],
      ),
    );
    if (action == 'whatsapp') {
      _sendBillOnWhatsApp();
      return;
    }
    if (action != 'checkout') return;
    await DatabaseHelper.instance.checkoutRoom(_chestNo);
    if (!mounted) return;
    _refreshData();
    _showMsg('Checkout ho gaya! Hisaab History me save hai ✅');
  }

  // ---------- Quick menu item ----------
  Future<void> _addQuickItem(String name, int price) async {
    final q = TextEditingController(text: '1');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add $name'),
        content: TextField(
          controller: q,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Quantity', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
              final qty = int.tryParse(q.text.trim()) ?? 0;
              if (qty <= 0) {
                _showMsg('Quantity kam se kam 1 rakho', isError: true);
                return;
              }
              final total = price * qty;
              final finalName = qty > 1 ? '$name (x$qty)' : name;
              await DatabaseHelper.instance
                  .addTransaction(_chestNo, finalName, total, false);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              _refreshData();
            },
            child: const Text('ADD'),
          ),
        ],
      ),
    );
    q.dispose();
  }

  // ---------- TTS ----------
  Future<void> _speakBill() async {
    if (_isSpeaking) {
      await _flutterTts.stop();
      if (mounted) setState(() => _isSpeaking = false);
      return;
    }
    setState(() => _isSpeaking = true);
    var textToSpeak = '$_roomName का हिसाब। ';
    textToSpeak += 'कुल खर्चा $_totalExpense रुपये। जमा हुए $_totalPaid रुपये। ';
    if (_balanceDue > 0) {
      textToSpeak += 'लेने बचे हैं $_balanceDue रुपये।';
    } else if (_balanceDue < 0) {
      textToSpeak += 'गेस्ट के ${_balanceDue.abs()} रुपये ज्यादा जमा हैं।';
    } else {
      textToSpeak += 'हिसाब बराबर है।';
    }
    await _flutterTts.speak(textToSpeak);
  }

  // ---------- PDF ----------
  String _pdfMoney(int v) =>
      'Rs. ${NumberFormat.decimalPattern('en_IN').format(v)}';

  Future<void> _generateAndPreviewPdf() async {
    // Hindi naam/item PDF me saaf dikhe — uske liye Devanagari font.
    // Font download na ho paya (offline) to default font se kaam chalega.
    pw.ThemeData? theme;
    try {
      final base = await PdfGoogleFonts.notoSansDevanagariRegular();
      final bold = await PdfGoogleFonts.notoSansDevanagariBold();
      theme = pw.ThemeData.withFont(base: base, bold: bold);
    } catch (_) {
      theme = null;
    }

    final pdf = pw.Document(theme: theme);
    final dateStr = DateFormat('dd-MM-yyyy').format(DateTime.now());
    // Bill me purani entries pehle (list screen par nayi pehle dikhti hai)
    final billItems = _transactions.reversed.toList();
    // Settings me dala gaya hotel/mess naam bill ke sabse upar
    final billTitle = _settings.hotelName.trim().isEmpty
        ? 'HOTEL STATEMENT'
        : _settings.hotelName.trim().toUpperCase();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) => [
          pw.Center(
            child: pw.Text(billTitle,
                style: pw.TextStyle(
                    fontSize: 24, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 16),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Customer: $_roomName'),
                  if (_roomNo.isNotEmpty) pw.Text('Room No: $_roomNo'),
                  pw.Text(
                      'Chest No: ${_chestDisplay.isEmpty ? _chestNo : _chestDisplay}'),
                  if (_phone.isNotEmpty) pw.Text('Phone: $_phone'),
                ],
              ),
              pw.Text('Date: $dateStr'),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Divider(),
          pw.Row(
            children: [
              pw.SizedBox(
                  width: 80,
                  child: pw.Text('Date',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
              pw.Expanded(
                  child: pw.Text('Item',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
              pw.SizedBox(
                width: 100,
                child: pw.Text('Amount',
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ),
            ],
          ),
          pw.Divider(),
          ...billItems.map((item) {
            final isCredit = item['is_advance'] == 1;
            final amt = (item['amount'] as num?)?.toInt() ?? 0;
            return pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Row(
                children: [
                  pw.SizedBox(
                      width: 80,
                      child: pw.Text(AppHelpers.formatDateOnly(
                          item['date'] as String?))),
                  pw.Expanded(
                      child: pw.Text(
                          '${item['title'] ?? ''}${isCredit ? ' (Paid)' : ''}')),
                  pw.SizedBox(
                    width: 100,
                    child: pw.Text(
                      isCredit ? '- ${_pdfMoney(amt)}' : _pdfMoney(amt),
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(
                          color: isCredit ? PdfColors.green : PdfColors.red),
                    ),
                  ),
                ],
              ),
            );
          }),
          pw.Divider(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [pw.Text('Total Bill: ${_pdfMoney(_totalExpense)}')],
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [pw.Text('Total Paid: ${_pdfMoney(_totalPaid)}')],
          ),
          pw.Divider(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text('BALANCE DUE: ${_pdfMoney(_balanceDue)}',
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold)),
            ],
          ),
          pw.SizedBox(height: 30),
          pw.Center(child: pw.Text('Thank you!')),
        ],
      ),
    );

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) => PdfPreviewScreen(doc: pdf, name: _roomName)),
    );
  }

  // ---------- WhatsApp ----------
  Future<void> _sendBillOnWhatsApp() async {
    final normalized = AppHelpers.normalizeIndianPhone(_phone);
    if (normalized == null) {
      _showMsg(
          'Sahi phone number save nahi hai! Home se Room Settings (⚙️) me number daalo.',
          isError: true);
      return;
    }
    final who = [
      if (_roomNo.isNotEmpty) 'Room $_roomNo',
      if (_chestDisplay.isNotEmpty) 'Chest $_chestDisplay',
    ].join(', ');
    final hotelLine = _settings.hotelName.trim().isEmpty
        ? ''
        : '*${_settings.hotelName.trim()}*\n';
    final buffer = StringBuffer(
        '$hotelLine*BILL: $_roomName${who.isEmpty ? '' : ' ($who)'}*\n------------------\n');
    for (final item in _transactions.reversed) {
      final isCredit = item['is_advance'] == 1;
      final amt = (item['amount'] as num?)?.toInt() ?? 0;
      buffer.writeln(
          '${AppHelpers.formatDateOnly(item['date'] as String?)} | ${item['title']}: ${isCredit ? 'PAID ' : ''}${AppHelpers.formatRupees(amt)}');
    }
    buffer.write(
        '------------------\n*Total Bill:* ${AppHelpers.formatRupees(_totalExpense)}\n*Paid:* ${AppHelpers.formatRupees(_totalPaid)}\n*PENDING:* ${AppHelpers.formatRupees(_balanceDue)}\n');
    final url = Uri.parse(
        'https://wa.me/$normalized?text=${Uri.encodeComponent(buffer.toString())}');
    try {
      final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!ok) {
        _showMsg('WhatsApp khul nahi paya — number check karo', isError: true);
      }
    } catch (e) {
      _showMsg('WhatsApp khul nahi paya: $e', isError: true);
    }
  }

  // ---------- Dhulai (Washing) — ON/OFF, counting, monthly cycle ----------
  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Purana format ('dd MMM yyyy') bhi chalega, naya ISO ('yyyy-MM-dd') bhi.
  DateTime? _parseWashingDate(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final iso = DateTime.tryParse(s);
    if (iso != null) return _dateOnly(iso);
    try {
      return _dateOnly(DateFormat('dd MMM yyyy').parse(s));
    } catch (_) {
      return null;
    }
  }

  String _fmtDay(DateTime d) => DateFormat('dd MMM yyyy').format(d);
  String _isoOf(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _toggleWashing(bool value) async {
    if (value) {
      // ON: counting aaj se shuru (chahe to neeche Date Edit se pichhli date kar sakte ho)
      await DatabaseHelper.instance.setWashingSettings(
        _chestNo,
        isOn: true,
        startDateIso: _isoOf(_dateOnly(DateTime.now())),
      );
      _refreshData();
      _showMsg(
          'Dhulai shuru ✅ Aaj se din count honge. Galat date hai to DATE EDIT karo.');
    } else {
      await DatabaseHelper.instance
          .setWashingSettings(_chestNo, isOn: false);
      _refreshData();
      _showMsg('Dhulai band kar di');
    }
  }

  /// Bhoolne par baad me sahi start date dalne ke liye (calendar se chuno).
  Future<void> _editWashingDate() async {
    final today = _dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _washingStart ?? today,
      firstDate: DateTime(2020),
      lastDate: today,
      helpText: 'Dhulai kab se shuru hui thi?',
    );
    if (picked == null) return;
    await DatabaseHelper.instance.setWashingSettings(
      _chestNo,
      isOn: true,
      startDateIso: _isoOf(_dateOnly(picked)),
    );
    _refreshData();
    _showMsg('Dhulai ki start date ${_fmtDay(picked)} kar di ✅');
  }

  /// BILL ADD: sabse purana pending mahina, warna chalta hua mahina.
  Future<void> _showWashingBillDialog() async {
    WashingMonth? target;
    for (final m in _washingMonths) {
      if (m.isPending) {
        target = m;
        break;
      }
    }
    if (target == null) {
      for (final m in _washingMonths) {
        if (m.isCurrent && m.remaining > 0) {
          target = m;
          break;
        }
      }
    }
    if (target == null) {
      if (_washingMonths.isEmpty) {
        _showMsg('Dhulai OFF hai — pehle upar switch ON karo', isError: true);
      } else {
        _showMsg('Dhulai ka sab bill ban chuka hai ✅ koi pending nahi');
      }
      return;
    }
    await _showMonthBillDialog(target);
  }

  /// Ek mahine ka dhulai bill hisaab me jodo (amount = bacha hua, edit hota hai).
  Future<void> _showMonthBillDialog(WashingMonth m) async {
    final c = TextEditingController(text: '${m.remaining}');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Dhulai Bill — ${m.fullLabel}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              m.isFullMonth
                  ? '${m.fullLabel}: pura mahina = ${AppHelpers.formatRupees(m.dueAmount)}'
                  : '${m.fullLabel}: ${m.serviceDays} din × ${AppHelpers.formatRupees(_settings.washingDailyRate)} = ${AppHelpers.formatRupees(m.dueAmount)}',
            ),
            if (m.billedAmount > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Pehle se bill bana: ${AppHelpers.formatRupees(m.billedAmount)} • Baki: ${AppHelpers.formatRupees(m.remaining)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: c,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Bill Amount (₹)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            const Text(
              'Poori rakam jodne par is mahine par ✓ Done lag jayega. Kam joda to baki Pending me rahega.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
              final amt = int.tryParse(c.text.trim()) ?? 0;
              if (amt <= 0) {
                _showMsg('Sahi amount daalo', isError: true);
                return;
              }
              await DatabaseHelper.instance.addWashingBillTransaction(
                _chestNo,
                monthKey: m.key,
                title: 'Dhulai — ${m.fullLabel}',
                amount: amt,
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              _refreshData();
              _showMsg('${m.fullLabel} ka dhulai bill jud gaya ✅');
            },
            child: const Text('BILL ADD KARO'),
          ),
        ],
      ),
    );
    c.dispose();
  }

  // ---------- Transaction edit/delete ----------
  Future<void> _showTransactionOptions(Map<String, dynamic> transaction) async {
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text('Edit Karo'),
              onTap: () {
                Navigator.pop(ctx);
                _showEditTransactionDialog(transaction);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete Karo'),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteTransaction(transaction);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditTransactionDialog(
      Map<String, dynamic> transaction) async {
    final i = TextEditingController(text: transaction['title']?.toString() ?? '');
    final p = TextEditingController(text: '${transaction['amount'] ?? ''}');
    var isPayment = transaction['is_advance'] == 1;

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Entry Edit Karo'),
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
                                    color: !isPayment
                                        ? Colors.white
                                        : Colors.black))),
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
                                    color: isPayment
                                        ? Colors.white
                                        : Colors.black))),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              TextField(
                controller: i,
                decoration: const InputDecoration(
                    labelText: 'Item / Note', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: p,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Amount', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('CANCEL')),
            ElevatedButton(
              onPressed: () async {
                final amount = int.tryParse(p.text.trim()) ?? 0;
                if (amount <= 0) {
                  _showMsg('Sahi amount daalo (0 se bada)', isError: true);
                  return;
                }
                var title = i.text.trim();
                if (title.isEmpty) {
                  title = isPayment ? 'Payment/Advance' : 'General Item';
                }
                await DatabaseHelper.instance.updateTransaction(
                  (transaction['id'] as num).toInt(),
                  title,
                  amount,
                  isAdvance: isPayment,
                );
                if (!dialogCtx.mounted) return;
                Navigator.pop(dialogCtx);
                _refreshData();
                _showMsg('Entry update ho gayi ✅');
              },
              child: const Text('UPDATE'),
            ),
          ],
        ),
      ),
    );
    i.dispose();
    p.dispose();
  }

  Future<void> _confirmDeleteTransaction(
      Map<String, dynamic> transaction) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Ye entry delete karein?'),
            content: Text(
                '${transaction['title']} — ${AppHelpers.formatRupees((transaction['amount'] as num?)?.toInt() ?? 0)}'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('NAHI')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('DELETE'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await DatabaseHelper.instance
        .deleteTransaction((transaction['id'] as num).toInt());
    _refreshData();
    _showMsg('Entry delete ho gayi');
  }

  // ---------- Voice ----------
  Future<void> _startListening() async {
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
    setState(() => _isListening = true);
    await _speechToText.listen(
      onResult: (result) {
        if (result.finalResult) {
          if (mounted) setState(() => _isListening = false);
          _processDirectEntry(result.recognizedWords);
        }
      },
      localeId: 'en_IN',
      listenFor: const Duration(seconds: 15),
      listenOptions: SpeechListenOptions(
        cancelOnError: false,
        partialResults: false,
      ),
    );
  }

  Future<void> _stopListening() async {
    await _speechToText.stop();
    if (!mounted) return;
    setState(() => _isListening = false);
  }

  void _processDirectEntry(String text) {
    if (text.trim().isEmpty) return;
    final result = VoiceParser.parseRequest(text);
    _showAddDialog(
      result['title'] as String,
      (result['amount'] as int?) ?? 0,
      initialQty: (result['quantity'] as int?) ?? 1,
      initialPayment: (result['isPaymentHint'] as bool?) ?? false,
    );
  }

  // ---------- Add dialog ----------
  Future<void> _showAddDialog(String initialItem, int initialPrice,
      {int initialQty = 1, bool initialPayment = false}) async {
    final i = TextEditingController(text: initialItem);
    final p = TextEditingController(
        text: initialPrice == 0 ? '' : '$initialPrice');
    final q = TextEditingController(text: '$initialQty');
    var isPayment = initialPayment;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            isPayment ? 'JAMA (Credit)' : 'KHARCHA (Debit)',
            style: TextStyle(
                color: isPayment ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold),
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
                            child: Text('Kharcha (Red)',
                                style: TextStyle(
                                    color: !isPayment
                                        ? Colors.white
                                        : Colors.black))),
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
                            child: Text('Jama (Green)',
                                style: TextStyle(
                                    color: isPayment
                                        ? Colors.white
                                        : Colors.black))),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              TextField(
                controller: i,
                decoration: InputDecoration(
                    labelText:
                        isPayment ? 'Note (e.g. Advance)' : 'Item Name',
                    border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: p,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Amount', border: OutlineInputBorder()),
                    ),
                  ),
                  if (!isPayment) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: q,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Qty', border: OutlineInputBorder()),
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
                child: const Text('Cancel')),
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
                    .addTransaction(_chestNo, title, total, isPayment);
                if (!dialogCtx.mounted) return;
                Navigator.pop(dialogCtx);
                _refreshData();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    i.dispose();
    p.dispose();
    q.dispose();
  }

  Widget _washingStatusText() {
    final title =
        'Dhulai (Washing) — ${AppHelpers.formatRupees(_settings.washingDailyRate)}/din • ${AppHelpers.formatRupees(_settings.washingMonthlyAmount)}/mahina';
    String sub;
    Color subColor = Colors.grey;
    if (!_isWashingOn) {
      sub = 'OFF — Sir ne dhulai nahi rakhi hai';
    } else if (_washingStart == null || _washingMonths.isEmpty) {
      sub = 'ON — start date set karo (DATE EDIT)';
      subColor = Colors.orange;
    } else {
      final pendingTotal =
          WashingHelper.pastPendingTotal(_washingMonths);
      final current =
          _washingMonths.where((m) => m.isCurrent).firstOrNull;
      if (pendingTotal > 0) {
        sub =
            '⚠️ Pending ${AppHelpers.formatRupees(pendingTotal)} — purane mahino ka bill baki hai';
        subColor = Colors.red;
      } else if (current != null) {
        sub = current.isDone
            ? '${current.fullLabel}: ✓ Done — bill ban gaya'
            : '${current.fullLabel} chalu hai: ${current.serviceDays} din × ${AppHelpers.formatRupees(_settings.washingDailyRate)} = ${AppHelpers.formatRupees(current.dueAmount)}';
        subColor = current.isDone ? Colors.green : Colors.blue;
      } else {
        sub = 'Start ${_fmtDay(_washingStart!)}';
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(sub, style: TextStyle(fontSize: 12, color: subColor)),
      ],
    );
  }

  /// Mahino ki strip: ✓ Done (hara) • Pending (laal) • chalta mahina (neela).
  /// Kisi month par tap karo to usi ka bill banega.
  Widget _washingMonthsRow() {
    if (!_isWashingOn || _washingMonths.isEmpty) {
      return const SizedBox.shrink();
    }
    final shown = _washingMonths.length <= 12
        ? _washingMonths
        : _washingMonths.sublist(_washingMonths.length - 12);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: Row(
            children: [
              for (final m in shown)
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 2),
                  child: _monthChip(m),
                ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Kisi mahine par tap karo → us month ka bill banega',
          style: TextStyle(fontSize: 10.5, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _monthChip(WashingMonth m) {
    final Color bg;
    final String statusLine;
    final String detailLine;
    if (m.isDone) {
      bg = Colors.green.shade700;
      statusLine = '✓ Done';
      detailLine = AppHelpers.formatRupees(m.dueAmount);
    } else if (m.isCurrent) {
      bg = Colors.blue.shade700;
      statusLine = m.remaining > 0
          ? '• Chalu hai'
          : '✓ Done';
      detailLine = m.billedAmount > 0
          ? '${AppHelpers.formatRupees(m.dueAmount)} (bill ${AppHelpers.formatRupees(m.billedAmount)})'
          : '${m.serviceDays} din • ${AppHelpers.formatRupees(m.dueAmount)}';
    } else {
      bg = Colors.red.shade700;
      statusLine = m.billedAmount > 0 ? '⏳ Aadha bill' : '⏳ Pending';
      detailLine = m.billedAmount > 0
          ? 'Baki ${AppHelpers.formatRupees(m.remaining)}'
          : AppHelpers.formatRupees(m.dueAmount);
    }
    return InkWell(
      onTap: () {
        if (m.isDone) {
          _showMsg('${m.fullLabel} ka bill ban chuka hai ✓');
        } else {
          _showMonthBillDialog(m);
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m.shortLabel,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
            Text(statusLine,
                style: const TextStyle(color: Colors.white, fontSize: 10.5)),
            Text(detailLine,
                style: const TextStyle(color: Colors.white70, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  // ---------- Build ----------
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final visible = _visibleTransactions;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_roomName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18)),
            if (_roomNo.isNotEmpty || _chestDisplay.isNotEmpty)
              Text(
                [
                  if (_roomNo.isNotEmpty) 'Room $_roomNo',
                  if (_chestDisplay.isNotEmpty) 'Chest $_chestDisplay',
                ].join(' • '),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
              ),
          ],
        ),
        actions: [
          IconButton(
              onPressed: _speakBill,
              icon: Icon(_isSpeaking ? Icons.volume_off : Icons.volume_up),
              tooltip: 'Hisaab Suno'),
          IconButton(
              onPressed: _sendBillOnWhatsApp,
              icon: const Icon(Icons.send),
              tooltip: 'WhatsApp Bill'),
          IconButton(
              onPressed: _generateAndPreviewPdf,
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: 'PDF Bill'),
          IconButton(
              onPressed: _checkoutRoom,
              icon: const Icon(Icons.cleaning_services_rounded),
              tooltip: 'Checkout / Clear Room'),
        ],
      ),
      body: Column(
        children: [
          // Balance card
          Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[800] : Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 5)],
              border: Border.all(
                  color: _balanceDue > 0 ? Colors.red : Colors.green, width: 2),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total Bill',
                        style: TextStyle(color: Colors.red)),
                    Text(AppHelpers.formatRupees(_totalExpense),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 18)),
                  ],
                ),
                Container(width: 1, height: 40, color: Colors.grey),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Paid', style: TextStyle(color: Colors.green)),
                    Text(AppHelpers.formatRupees(_totalPaid),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 18)),
                  ],
                ),
                Container(width: 1, height: 40, color: Colors.grey),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('LENA (Due)',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black)),
                    Text(
                      AppHelpers.formatRupees(_balanceDue),
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color:
                              _balanceDue > 0 ? Colors.red : Colors.green),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Dhulai (Washing) section — ON/OFF, din counting, due date, date edit
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[800] : Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 5)],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.local_laundry_service,
                        color: _isWashingOn ? Colors.blue : Colors.grey),
                    const SizedBox(width: 10),
                    Expanded(child: _washingStatusText()),
                    Switch(value: _isWashingOn, onChanged: _toggleWashing),
                  ],
                ),
                _washingMonthsRow(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_isWashingOn)
                      TextButton.icon(
                        onPressed: _editWashingDate,
                        icon: const Icon(Icons.edit_calendar, size: 16),
                        label: const Text('DATE EDIT'),
                      ),
                    TextButton.icon(
                      onPressed: _showWashingBillDialog,
                      icon: const Icon(Icons.receipt_long, size: 16),
                      label: const Text('BILL ADD'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),

          // Quick menu
          if (_menuItems.isNotEmpty)
            SizedBox(
              height: 50,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(vertical: 5),
                itemCount: _menuItems.length,
                itemBuilder: (context, index) {
                  final item = _menuItems[index];
                  final price = (item['price'] as num?)?.toInt() ?? 0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: ActionChip(
                      avatar: Text(item['icon']?.toString() ?? '🍽️'),
                      label: Text(
                          '${item['name']} ${AppHelpers.formatRupees(price)}'),
                      onPressed: () => _addQuickItem(
                          item['name']?.toString() ?? 'Item', price),
                    ),
                  );
                },
              ),
            ),

          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Item khojo... (e.g. Chai)',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const Divider(height: 1),

          // Transactions list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : visible.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _searchQuery.isEmpty
                                ? 'Abhi is room ka koi hisaab nahi hai.\nNeeche "Add / Pay" se pehli entry daalo ya mic se bolo 🎙️'
                                : '"$_searchQuery" naam ki koi entry nahi mili.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 90),
                        itemCount: visible.length,
                        itemBuilder: (ctx, idx) {
                          final item = visible[idx];
                          final isCredit = item['is_advance'] == 1;
                          final amt =
                              (item['amount'] as num?)?.toInt() ?? 0;
                          return Card(
                            color: isCredit
                                ? Colors.green[50]
                                : (isDark ? Colors.grey[900] : Colors.white),
                            margin: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            child: ListTile(
                              onTap: () => _showTransactionOptions(item),
                              onLongPress: () =>
                                  _showTransactionOptions(item),
                              leading: Icon(
                                isCredit
                                    ? Icons.arrow_circle_down
                                    : Icons.arrow_circle_up,
                                color: isCredit ? Colors.green : Colors.red,
                              ),
                              title: Text(
                                item['title']?.toString() ?? '',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isCredit
                                      ? Colors.green[900]
                                      : (isDark
                                          ? Colors.white
                                          : Colors.black),
                                ),
                              ),
                              subtitle: Text(
                                AppHelpers.formatDateTime(
                                    item['date'] as String?),
                                style: TextStyle(
                                    color: isDark
                                        ? Colors.grey
                                        : Colors.black54),
                              ),
                              trailing: Text(
                                isCredit
                                    ? '- ${AppHelpers.formatRupees(amt)}'
                                    : AppHelpers.formatRupees(amt),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: isCredit
                                      ? Colors.green[800]
                                      : Colors.red,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          FloatingActionButton.extended(
            heroTag: 'manual_add',
            onPressed: () => _showAddDialog('', 0),
            backgroundColor: Colors.orange,
            icon: const Icon(Icons.add),
            label: const Text('Add / Pay'),
          ),
          FloatingActionButton.extended(
            heroTag: 'voice_add',
            onPressed: () => _isListening ? _stopListening() : _startListening(),
            backgroundColor: _isListening ? Colors.green : Colors.blue,
            icon: Icon(_isListening ? Icons.mic_off : Icons.mic),
            label: Text(_isListening ? 'रुकें' : 'बोलें'),
          ),
        ],
      ),
    );
  }
}

class PdfPreviewScreen extends StatelessWidget {
  final pw.Document doc;
  final String name;
  const PdfPreviewScreen({super.key, required this.doc, required this.name});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bill Preview')),
      body: PdfPreview(
        build: (format) => doc.save(),
        initialPageFormat: PdfPageFormat.a4,
        pdfFileName: 'Bill_$name.pdf',
      ),
    );
  }
}
