import 'dart:io';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui'; 

import '../data/database_helper.dart';
import '../utils/voice_parser.dart';
import '../main.dart';
import 'chest_detail_screen.dart';
import 'menu_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final SpeechToText _speechToText = SpeechToText();
  bool _isListening = false;
  List<Map<String, dynamic>> _chests = [];
  List<Map<String, dynamic>> _notes = [];
  bool _isLoading = true;

  final List<Color> _cardColors = [
    const Color(0xFF6C5CE7), const Color(0xFF00B894),
    const Color(0xFFE17055), const Color(0xFF0984E3),
    const Color(0xFFFD79A8), const Color(0xFFFDCB6E),
  ];

  @override
  void initState() {
    super.initState();
    _refreshAll();
    _initSpeech();
  }

  void _initSpeech() async {
    await _speechToText.initialize();
    setState(() {});
  }

  Future<void> _refreshAll() async {
    setState(() => _isLoading = true);
    final chests = await DatabaseHelper.instance.getAllChests();
    final notes = await DatabaseHelper.instance.getPendingNotes();
    setState(() {
      _chests = chests;
      _notes = notes;
      _isLoading = false;
    });
  }

  Future<void> _pickImageForChest(int chestNumber) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      await DatabaseHelper.instance.updateChestImage(chestNumber, image.path);
      _refreshAll();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Photo Updated! 📸")));
    }
  }

  Future<void> _exportFullReport() async {
    try {
      final allData = await DatabaseHelper.instance.getAllTransactionsForReport();
      if (allData.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No Data"), backgroundColor: Colors.red));
        return;
      }
      String csvData = "Date,Room Name,Item,Amount\n";
      for (var row in allData) csvData += "${row['date']},${row['name']},${row['title']},${row['amount']}\n";
      final dir = await getApplicationDocumentsDirectory();
      final path = "${dir.path}/Hotel_Report_${DateTime.now().millisecondsSinceEpoch}.csv";
      await File(path).writeAsString(csvData);
      await Share.shareXFiles([XFile(path)], text: "Report");
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    }
  }

  void _startListening() async { await _speechToText.listen(onResult: (result) {if (result.finalResult) {_processSmartVoice(result.recognizedWords); setState(() => _isListening = false);}}, localeId: "en_IN", listenFor: const Duration(seconds: 10), cancelOnError: false, partialResults: false); setState(() => _isListening = true); }
  void _stopListening() async { await _speechToText.stop(); setState(() => _isListening = false); }

  void _processSmartVoice(String text) async {
    Map<String, dynamic> result = VoiceParser.parseRequest(text);
    int? chestNo = result['chestNumber'];
    if (chestNo != null) { _showExpenseDialog(chestNo, result['title'], result['amount'] ?? 0, text); } 
    else { await DatabaseHelper.instance.addNote(text); _refreshAll(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Note Saved!"), backgroundColor: Colors.orange)); }
  }

  // --- 🔥 UPDATED: QUANTITY SUPPORT ADDED 🔥 ---
  void _showExpenseDialog(int chestNo, String item, int amount, String originalText) {
    bool chestExists = _chests.any((c) => c['number'] == chestNo);
    if (!chestExists) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Chest $chestNo nahi mila!"), backgroundColor: Colors.red)); return; }
    
    TextEditingController i = TextEditingController(text: item); 
    TextEditingController p = TextEditingController(text: amount.toString());
    TextEditingController q = TextEditingController(text: "1"); // Default Quantity 1

    showDialog(
      context: context, 
      barrierDismissible: false, 
      builder: (context) => AlertDialog(
        title: Text("Add to Room $chestNo"), 
        content: Column(
          mainAxisSize: MainAxisSize.min, 
          children: [
            TextField(controller: i, decoration: const InputDecoration(labelText: "Item Name", border: OutlineInputBorder())), 
            SizedBox(height: 10), 
            Row(
              children: [
                Expanded(child: TextField(controller: p, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Price (Per Item)", border: OutlineInputBorder()))),
                SizedBox(width: 10),
                Expanded(child: TextField(controller: q, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Quantity", border: OutlineInputBorder()))),
              ],
            )
          ]
        ), 
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(color: Colors.red))), 
          ElevatedButton(
            onPressed: () async { 
              int price = int.tryParse(p.text) ?? 0;
              int qty = int.tryParse(q.text) ?? 1;
              int total = price * qty; // Auto Calculate Total
              String finalTitle = qty > 1 ? "${i.text} (x$qty)" : i.text; // Add (x2) if more than 1

              await DatabaseHelper.instance.addTransaction(chestNo, finalTitle, total, false); 
              Navigator.pop(context); 
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Saved! ₹$total ✅"), backgroundColor: Colors.green)); 
            }, 
            child: const Text("SAVE")
          )
        ]
      )
    );
  }

  void _showEditChestDialog(Map<String, dynamic> chest) {
    TextEditingController n = TextEditingController(text: chest['name']); TextEditingController p = TextEditingController(text: chest['phone']);
    showDialog(context: context, builder: (context) => AlertDialog(title: Text("Room ${chest['number']} Settings"), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: n, decoration: const InputDecoration(labelText: "Name")), SizedBox(height: 10), TextField(controller: p, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: "Phone")), const SizedBox(height: 20), ElevatedButton.icon(onPressed: () {Navigator.pop(context); _pickImageForChest(chest['number']);}, icon: const Icon(Icons.photo_camera), label: const Text("Change Photo"), style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white))]), actions: [TextButton(onPressed: () async { bool c = await showDialog(context: context, builder: (c) => AlertDialog(title: const Text("Delete Room?"), actions: [TextButton(onPressed: ()=>Navigator.pop(c, true), child: const Text("Yes"))])) ?? false; if(c) { await DatabaseHelper.instance.deleteChest(chest['number']); _refreshAll(); Navigator.pop(context); } }, child: const Text("DELETE", style: TextStyle(color: Colors.red))), ElevatedButton(onPressed: () async { await DatabaseHelper.instance.updateChestDetails(chest['number'], n.text, p.text); _refreshAll(); Navigator.pop(context); }, child: const Text("UPDATE"))]));
  }
  void _deleteNote(int id) async { await DatabaseHelper.instance.deleteNote(id); _refreshAll(); }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text("RoomService Pro", style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 24, color: isDark ? Colors.white : Colors.black87)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
           IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const MenuScreen())), icon: Icon(Icons.restaurant_menu, color: isDark ? Colors.white : Colors.black), tooltip: "Menu"),
           IconButton(onPressed: _exportFullReport, icon: Icon(Icons.analytics, color: isDark ? Colors.white : Colors.black), tooltip: "Export"),
           IconButton(onPressed: () => MyApp.toggleTheme(context), icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode, color: isDark ? Colors.white : Colors.black)),
        ],
      ),
      body: Column(
        children: [
          if (_notes.isNotEmpty) 
             Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                height: 50,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _notes.length, 
                  itemBuilder: (ctx, i) => Container(
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: isDark ? Colors.grey[800] : Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade300)),
                    child: Row(children: [Icon(Icons.circle, color: Colors.orange, size: 10), const SizedBox(width: 8), Text(_notes[i]['content'], style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black)), const SizedBox(width: 5), GestureDetector(onTap: () => _deleteNote(_notes[i]['id']), child: Icon(Icons.close, color: Colors.red, size: 16))]),
                  )
                ),
             ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 5),
              child: GridView.builder(
                itemCount: _chests.length + 1,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 0.9, crossAxisSpacing: 16, mainAxisSpacing: 16),
                itemBuilder: (context, index) {
                  if (index == _chests.length) return _buildAddButton(isDark);
                  Color themeColor = _cardColors[index % _cardColors.length];
                  return _buildChestCard(_chests[index], isDark, themeColor);
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: GestureDetector(
        onTap: () => _isListening ? _stopListening() : _startListening(),
        child: Container(
          height: 70, width: 70,
          decoration: BoxDecoration(shape: BoxShape.circle, color: _isListening ? Colors.red : (isDark ? Colors.white : Colors.black), boxShadow: [BoxShadow(color: _isListening ? Colors.red.withOpacity(0.4) : Colors.black.withOpacity(0.2), blurRadius: 15, spreadRadius: 2)]),
          child: Icon(_isListening ? Icons.mic : Icons.mic_none, color: _isListening ? Colors.white : (isDark ? Colors.black : Colors.white), size: 30),
        ),
      ),
    );
  }

  Widget _buildChestCard(Map<String, dynamic> chest, bool isDark, Color themeColor) {
    String customName = chest['name'] ?? "";
    bool isDefaultName = customName == "Room ${chest['number']}"; 
    String? imagePath = chest['image_path'];
    bool hasImage = imagePath != null && imagePath.isNotEmpty && File(imagePath).existsSync();

    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ChestDetailScreen(chestData: chest))),
      onLongPress: () => _showEditChestDialog(chest),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: hasImage ? null : LinearGradient(colors: [themeColor, themeColor.withOpacity(0.8)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          image: hasImage ? DecorationImage(image: FileImage(File(imagePath)), fit: BoxFit.cover) : null,
          boxShadow: [BoxShadow(color: themeColor.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 6))],
        ),
        child: Stack(
          children: [
            if (hasImage) Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: Colors.black45)),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: hasImage ? Colors.white30 : Colors.white.withOpacity(0.2), shape: BoxShape.circle), child: Icon(Icons.bed, color: Colors.white, size: 20)), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)), child: Text("${chest['number']}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))]),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(isDefaultName ? "Room" : customName, style: GoogleFonts.poppins(fontSize: 14, color: Colors.white70, fontWeight: FontWeight.w500)), Text(isDefaultName ? "${chest['number']}" : "", style: GoogleFonts.poppins(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold, height: 1.0))])
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
      onTap: () {
        TextEditingController c = TextEditingController();
        showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("New Chest"), content: TextField(controller: c, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Number")), actions: [ElevatedButton(onPressed: () async {if(c.text.isNotEmpty) {await DatabaseHelper.instance.addChest(int.parse(c.text)); _refreshAll(); Navigator.pop(ctx);}}, child: const Text("Add"))]));
      },
      child: Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: isDark ? Colors.grey[800] : Colors.white, border: Border.all(color: Colors.grey.shade300, width: 2, style: BorderStyle.solid)),
        child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add, size: 40, color: Colors.grey), Text("Add Room", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))])),
      ),
    );
  }
}