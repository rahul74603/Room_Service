import 'package:flutter/material.dart';
import '../data/database_helper.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  List<Map<String, dynamic>> _menuItems = [];
  
  @override
  void initState() {
    super.initState();
    _refreshMenu();
  }

  void _refreshMenu() async {
    final data = await DatabaseHelper.instance.getMenuItems();
    setState(() { _menuItems = data; });
  }

  void _addItem() {
    TextEditingController nameC = TextEditingController();
    TextEditingController priceC = TextEditingController();
    TextEditingController iconC = TextEditingController(text: "🍽️"); // Default Icon

    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("New Item"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameC, decoration: const InputDecoration(labelText: "Name (e.g. Maggi)")),
        const SizedBox(height: 10),
        TextField(controller: priceC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Price (e.g. 50)")),
        const SizedBox(height: 10),
        TextField(controller: iconC, decoration: const InputDecoration(labelText: "Icon (Emoji)")),
      ]),
      actions: [
        ElevatedButton(onPressed: () async {
          if(nameC.text.isNotEmpty && priceC.text.isNotEmpty) {
            await DatabaseHelper.instance.addMenuItem(nameC.text, int.parse(priceC.text), iconC.text);
            Navigator.pop(ctx);
            _refreshMenu();
          }
        }, child: const Text("Add"))
      ],
    ));
  }

  void _deleteItem(int id) async {
    await DatabaseHelper.instance.deleteMenuItem(id);
    _refreshMenu();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Menu Settings 📜")),
      body: ListView.builder(
        itemCount: _menuItems.length,
        itemBuilder: (ctx, i) {
          final item = _menuItems[i];
          return Card(
            child: ListTile(
              leading: Text(item['icon'], style: const TextStyle(fontSize: 24)),
              title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("₹ ${item['price']}"),
              trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteItem(item['id'])),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(onPressed: _addItem, child: const Icon(Icons.add)),
    );
  }
}