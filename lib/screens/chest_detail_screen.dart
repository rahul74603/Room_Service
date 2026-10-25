import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../data/database_helper.dart';
import '../utils/voice_parser.dart';

class ChestDetailScreen extends StatefulWidget {
  final Map<String, dynamic> chestData;
  const ChestDetailScreen({super.key, required this.chestData});

  @override
  State<ChestDetailScreen> createState() => _ChestDetailScreenState();
}

class _ChestDetailScreenState extends State<ChestDetailScreen> {
  final SpeechToText _speechToText = SpeechToText();
  bool _isListening = false;
  final FlutterTts _flutterTts = FlutterTts();
  bool _isSpeaking = false;

  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _menuItems = []; 
  
  // --- 💰 NEW BALANCE VARIABLES ---
  int _totalExpense = 0;  // Kul Kharcha (Debit)
  int _totalPaid = 0;     // Kul Jama (Credit)
  int _balanceDue = 0;    // Baki/Lena (Balance)

  bool _isLoading = true;
  bool _isWashingOn = false;
  String _washingStartDate = "";

  @override
  void initState() {
    super.initState();
    _refreshData();
    _initSpeech();
    _initTts();
  }

  void _initSpeech() async {
    await _speechToText.initialize();
    setState(() {});
  }

  void _initTts() async {
    await _flutterTts.setLanguage("hi-IN");
    await _flutterTts.setSpeechRate(0.4);
    await _flutterTts.setPitch(1.0);
    _flutterTts.setCompletionHandler(() => setState(() => _isSpeaking = false));
  }

  // --- 🔥 UPDATED: CALCULATION LOGIC (ADVANCE/CREDIT) 🔥 ---
  Future<void> _refreshData() async {
    setState(() => _isLoading = true);
    final chest = await DatabaseHelper.instance.getChest(widget.chestData['number']);
    final data = await DatabaseHelper.instance.getTransactions(widget.chestData['number']);
    final menu = await DatabaseHelper.instance.getMenuItems();

    int expense = 0;
    int paid = 0;

    for (var item in data) {
      if (item['is_advance'] == 1) {
        paid += (item['amount'] as int); // Green (Jama)
      } else {
        expense += (item['amount'] as int); // Red (Kharcha)
      }
    }

    setState(() {
      _isWashingOn = chest['is_washing_on'] == 1;
      _washingStartDate = chest['washing_start_date'] ?? "";
      _transactions = data;
      _totalExpense = expense;
      _totalPaid = paid;
      _balanceDue = expense - paid; // Baki Paisa
      _menuItems = menu;
      _isLoading = false;
    });
  }

  void _checkoutRoom() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Checkout / Clear Room?"),
        content: Text("Total Baki: ₹$_balanceDue\n\nक्या गेस्ट जा रहा है? सब डिलीट हो जाएगा।"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("NO")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              await DatabaseHelper.instance.clearRoom(widget.chestData['number']);
              Navigator.pop(ctx);
              _refreshData();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Room Cleared! ✅"), backgroundColor: Colors.green));
            },
            child: const Text("YES, CLEAR"),
          )
        ],
      ),
    );
  }

  // --- MENU CLICK (Default Expense) ---
  void _addQuickItem(String name, int price) {
    TextEditingController q = TextEditingController(text: "1");
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Add $name"),
        content: TextField(controller: q, keyboardType: TextInputType.number, autofocus: true, decoration: const InputDecoration(labelText: "Quantity", border: OutlineInputBorder())),
        actions: [
          ElevatedButton(
            onPressed: () async {
              int qty = int.tryParse(q.text) ?? 1;
              int total = price * qty;
              String finalName = qty > 1 ? "$name (x$qty)" : name;
              // Menu items hamesha kharcha hote hain (isAdvance = false)
              await DatabaseHelper.instance.addTransaction(widget.chestData['number'], finalName, total, false);
              Navigator.pop(ctx);
              _refreshData();
            },
            child: const Text("ADD"),
          )
        ],
      )
    );
  }

  void _speakBill() async {
    if (_isSpeaking) { await _flutterTts.stop(); setState(() => _isSpeaking = false); return; }
    setState(() => _isSpeaking = true);
    String textToSpeak = "चेस्ट नंबर ${widget.chestData['number']} का हिसाब। ";
    textToSpeak += "कुल खर्चा $_totalExpense रुपये। जमा हुए $_totalPaid रुपये। ";
    
    if (_balanceDue > 0) {
      textToSpeak += "लेने बचे हैं $_balanceDue रुपये।";
    } else if (_balanceDue < 0) {
      textToSpeak += "गेस्ट के ${_balanceDue.abs()} रुपये ज्यादा जमा हैं।";
    } else {
      textToSpeak += "हिसाब बराबर है।";
    }
    await _flutterTts.speak(textToSpeak);
  }

  Future<void> _generateAndPreviewPdf() async {
    final pdf = pw.Document();
    String customerName = widget.chestData['name'];
    String phone = widget.chestData['phone'].toString();
    String date = DateFormat('dd-MM-yyyy').format(DateTime.now());
    pdf.addPage(pw.Page(pageFormat: PdfPageFormat.a4, build: (pw.Context context) { return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Center(child: pw.Text("HOTEL STATEMENT", style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold))), pw.SizedBox(height: 20),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text("Customer: $customerName"), pw.Text("Phone: $phone")]), pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text("Date: $date")])]),
              pw.Divider(), 
              ..._transactions.map((item) { 
                bool isCredit = item['is_advance'] == 1;
                return pw.Row(children: [
                  pw.Expanded(flex: 3, child: pw.Text(item['title'])), 
                  pw.Expanded(flex: 1, child: pw.Text(isCredit ? "- Rs. ${item['amount']}" : "Rs. ${item['amount']}", textAlign: pw.TextAlign.right, style: pw.TextStyle(color: isCredit ? PdfColors.green : PdfColors.red)))
                ]); 
              }).toList(),
              pw.Divider(), 
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [pw.Text("Total Bill: Rs. $_totalExpense")]),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [pw.Text("Total Paid: Rs. $_totalPaid")]),
              pw.Divider(),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [pw.Text("BALANCE DUE: Rs. $_balanceDue", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))]),
            ]); },),);
    Navigator.push(context, MaterialPageRoute(builder: (context) => PdfPreviewScreen(doc: pdf, name: customerName)));
  }

  void _sendBillOnWhatsApp() async {
    String phone = widget.chestData['phone'] ?? "";
    if (phone.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Phone number save nahi hai!"), backgroundColor: Colors.red)); return; }
    String message = "*BILL: ${widget.chestData['name']}*\n------------------\n";
    for (var item in _transactions) { 
      bool isCredit = item['is_advance'] == 1;
      message += "${item['title']}: ${isCredit ? 'PAID ' : ''}₹${item['amount']}\n"; 
    }
    message += "------------------\n*Total Bill:* ₹$_totalExpense\n*Paid:* ₹$_totalPaid\n*PENDING:* ₹$_balanceDue\n";
    final Uri url = Uri.parse("https://wa.me/91$phone?text=${Uri.encodeComponent(message)}");
    try { await launchUrl(url, mode: LaunchMode.externalApplication); } catch (e) { /* Error */ }
  }

  void _toggleWashing(bool value) async { String date = value ? DateFormat('dd MMM yyyy').format(DateTime.now()) : ""; await DatabaseHelper.instance.updateWashingStatus(widget.chestData['number'], value, date); _refreshData(); }
  void _addWashingBill() { showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("Washing Bill"), content: const Text("Add ₹1500 charge?"), actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text("Cancel")), ElevatedButton(onPressed: () async { await DatabaseHelper.instance.addTransaction(widget.chestData['number'], "Washing Charge", 1500, false); Navigator.pop(ctx); _refreshData(); }, child: const Text("Add"))])); }
  void _showEditDeleteOption(Map<String, dynamic> transaction) { showModalBottomSheet(context: context, builder: (ctx) => Wrap(children: [ListTile(leading: const Icon(Icons.delete, color: Colors.red), title: const Text("Delete"), onTap: () { Navigator.pop(ctx); _confirmDelete(transaction['id']); })])); }
  void _confirmDelete(int id) async { await DatabaseHelper.instance.deleteTransaction(id); _refreshData(); }
  
  void _startListening() async { await _speechToText.listen(onResult: (result) {if (result.finalResult) {_processDirectEntry(result.recognizedWords); setState(() => _isListening = false);}}, localeId: "en_IN", listenFor: const Duration(seconds: 10), cancelOnError: false, partialResults: false); setState(() => _isListening = true); }
  void _stopListening() async { await _speechToText.stop(); setState(() => _isListening = false); }
  void _processDirectEntry(String text) { Map<String, dynamic> result = VoiceParser.parseRequest(text); _showAddDialog(result['title'], result['amount'] ?? 0); }
  
  // --- 🔥 UPDATED: DIALOG WITH CREDIT/DEBIT TOGGLE 🔥 ---
  void _showAddDialog(String initialItem, int initialPrice) { 
    TextEditingController i = TextEditingController(text: initialItem); 
    TextEditingController p = TextEditingController(text: initialPrice == 0 ? "" : initialPrice.toString()); 
    TextEditingController q = TextEditingController(text: "1");
    
    // Default: Kharcha (Red)
    bool isPayment = false; 

    showDialog(
      context: context, 
      barrierDismissible: false, 
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(isPayment ? "JAMA (Credit)" : "KHARCHA (Debit)", style: TextStyle(color: isPayment ? Colors.green : Colors.red, fontWeight: FontWeight.bold)), 
            content: Column(
              mainAxisSize: MainAxisSize.min, 
              children: [
                // Toggle Button
                Row(
                  children: [
                    Expanded(child: InkWell(onTap: () => setState(() => isPayment = false), child: Container(padding: const EdgeInsets.all(10), color: !isPayment ? Colors.red : Colors.grey[200], child: Center(child: Text("Kharcha (Red)", style: TextStyle(color: !isPayment ? Colors.white : Colors.black)))))),
                    Expanded(child: InkWell(onTap: () => setState(() => isPayment = true), child: Container(padding: const EdgeInsets.all(10), color: isPayment ? Colors.green : Colors.grey[200], child: Center(child: Text("Jama (Green)", style: TextStyle(color: isPayment ? Colors.white : Colors.black)))))),
                  ],
                ),
                SizedBox(height: 15),
                TextField(controller: i, decoration: InputDecoration(labelText: isPayment ? "Note (e.g. Advance)" : "Item Name", border: const OutlineInputBorder())), 
                SizedBox(height: 10), 
                Row(children: [
                  Expanded(child: TextField(controller: p, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Amount", border: OutlineInputBorder()))),
                  SizedBox(width: 10),
                  // Payment me Quantity nahi chahiye, sirf item me
                  if(!isPayment) Expanded(child: TextField(controller: q, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Qty", border: OutlineInputBorder())))
                ])
              ]
            ), 
            actions: [
              TextButton(onPressed: ()=>Navigator.pop(context), child: const Text("Cancel")), 
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: isPayment ? Colors.green : Colors.red, foregroundColor: Colors.white),
                onPressed: () async { 
                  if(p.text.isNotEmpty) { 
                    int price = int.tryParse(p.text) ?? 0;
                    int qty = int.tryParse(q.text) ?? 1;
                    int total = price * qty;
                    
                    // Agar payment hai, to quantity use mat karo, bas naam
                    String finalName = (!isPayment && qty > 1) ? "${i.text} (x$qty)" : (i.text.isEmpty ? "Payment/Advance" : i.text);

                    await DatabaseHelper.instance.addTransaction(widget.chestData['number'], finalName, total, isPayment); // isPayment Pass kar diya
                    Navigator.pop(context); 
                    _refreshData(); 
                  } 
                }, 
                child: const Text("Save")
              )
            ]
          );
        }
      )
    ); 
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chestData['name']),
        actions: [
          IconButton(onPressed: _speakBill, icon: Icon(_isSpeaking ? Icons.volume_off : Icons.volume_up), tooltip: "Hisaab Suno"),
          IconButton(onPressed: _sendBillOnWhatsApp, icon: const Icon(Icons.send), tooltip: "WhatsApp Bill"),
          IconButton(onPressed: _generateAndPreviewPdf, icon: const Icon(Icons.picture_as_pdf), tooltip: "PDF Bill"),
          IconButton(onPressed: _checkoutRoom, icon: const Icon(Icons.cleaning_services_rounded), tooltip: "Clear Room"),
        ],
      ),
      body: Column(
        children: [
          // --- 📊 BALANCE CARD (Green/Red Logic) ---
          Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[800] : Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)],
              border: Border.all(color: _balanceDue > 0 ? Colors.red : Colors.green, width: 2)
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Total Bill", style: TextStyle(color: Colors.red)), Text("₹$_totalExpense", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))]),
                Container(width: 1, height: 40, color: Colors.grey),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Paid", style: TextStyle(color: Colors.green)), Text("₹$_totalPaid", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))]),
                Container(width: 1, height: 40, color: Colors.grey),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text("LENA (Due)", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)), 
                  Text("₹$_balanceDue", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _balanceDue > 0 ? Colors.red : Colors.green))
                ]),
              ],
            ),
          ),
          
          if (_menuItems.isNotEmpty)
            Container(
              height: 50,
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _menuItems.length,
                itemBuilder: (context, index) {
                  final item = _menuItems[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: ActionChip(
                      avatar: Text(item['icon']),
                      label: Text("${item['name']} ₹${item['price']}"),
                      onPressed: () => _addQuickItem(item['name'], item['price']),
                    ),
                  );
                },
              ),
            ),
          const Divider(height: 1),

          // --- 📝 LIST WITH COLOR CODING ---
          Expanded(
            child: _isLoading ? const Center(child: CircularProgressIndicator()) : ListView.builder(
              itemCount: _transactions.length, 
              itemBuilder: (ctx, i) { 
                final item = _transactions[i]; 
                bool isCredit = item['is_advance'] == 1; // Check if Payment
                
                return Card(
                  color: isCredit ? Colors.green[50] : (isDark ? Colors.grey[900] : Colors.white),
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: ListTile(
                    onLongPress: () => _showEditDeleteOption(item), 
                    leading: Icon(
                      isCredit ? Icons.arrow_circle_down : Icons.arrow_circle_up, 
                      color: isCredit ? Colors.green : Colors.red
                    ), 
                    title: Text(item['title'], style: TextStyle(fontWeight: FontWeight.bold, color: isCredit ? Colors.green[900] : (isDark ? Colors.white : Colors.black))), 
                    subtitle: Text(DateFormat('dd MMM').format(DateTime.parse(item['date'])), style: TextStyle(color: isDark ? Colors.grey : Colors.black54)), 
                    trailing: Text(
                      isCredit ? "- ₹${item['amount']}" : "₹${item['amount']}", // Minus sign for credit
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isCredit ? Colors.green[800] : Colors.red)
                    )
                  ),
                ); 
              }
            )
          ),
        ],
      ),
      
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [FloatingActionButton.extended(heroTag: "m", onPressed: () => _showAddDialog("", 0), backgroundColor: Colors.orange, icon: const Icon(Icons.add), label: const Text("Add / Pay")), FloatingActionButton.extended(heroTag: "v", onPressed: () => _isListening ? _stopListening() : _startListening(), backgroundColor: _isListening ? Colors.green : Colors.blue, icon: Icon(_isListening ? Icons.mic_off : Icons.mic), label: Text(_isListening ? "रुकें" : "बोलें"))]),
    );
  }
}

class PdfPreviewScreen extends StatelessWidget {
  final pw.Document doc; final String name; const PdfPreviewScreen({super.key, required this.doc, required this.name});
  @override Widget build(BuildContext context) { return Scaffold(appBar: AppBar(title: const Text("Bill Preview")), body: PdfPreview(build: (format) => doc.save(), initialPageFormat: PdfPageFormat.a4, pdfFileName: "Bill_$name.pdf")); }
}