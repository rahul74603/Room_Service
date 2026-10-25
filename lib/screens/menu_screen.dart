import 'package:flutter/material.dart';

import '../data/database_helper.dart';
import '../utils/helpers.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  List<Map<String, dynamic>> _menuItems = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshMenu();
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

  Future<void> _refreshMenu() async {
    final data = await DatabaseHelper.instance.getMenuItems();
    if (!mounted) return;
    setState(() {
      _menuItems = data;
      _isLoading = false;
    });
  }

  /// Add aur Edit dono ke liye ek hi dialog (item == null ho to Add).
  Future<void> _showItemDialog({Map<String, dynamic>? item}) async {
    final isEdit = item != null;
    final editId = item != null ? (item['id'] as num).toInt() : -1;
    final nameC = TextEditingController(text: item?['name']?.toString() ?? '');
    final priceC =
        TextEditingController(text: isEdit ? '${item['price'] ?? ''}' : '');
    final iconC =
        TextEditingController(text: item?['icon']?.toString() ?? '🍽️');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Item Edit Karo' : 'New Item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameC,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'Name (e.g. Maggi)')),
            const SizedBox(height: 10),
            TextField(
              controller: priceC,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Price (e.g. 50)'),
            ),
            const SizedBox(height: 10),
            TextField(
                controller: iconC,
                decoration: const InputDecoration(labelText: 'Icon (Emoji)')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
              final name = nameC.text.trim();
              final price = int.tryParse(priceC.text.trim());
              if (name.isEmpty) {
                _showMsg('Item ka naam to daalo', isError: true);
                return;
              }
              if (price == null || price <= 0) {
                _showMsg('Sahi price daalo (0 se bada)', isError: true);
                return;
              }
              var icon = iconC.text.trim();
              if (icon.isEmpty) icon = '🍽️';
              if (isEdit) {
                await DatabaseHelper.instance.updateMenuItem(
                    (item['id'] as num).toInt(), name, price, icon);
              } else {
                await DatabaseHelper.instance.addMenuItem(name, price, icon);
              }
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              _refreshMenu();
              _showMsg(isEdit ? 'Item update ho gaya ✅' : 'Item add ho gaya ✅');
            },
            child: Text(isEdit ? 'UPDATE' : 'ADD'),
          ),
        ],
      ),
    );
    nameC.dispose();
    priceC.dispose();
    iconC.dispose();
  }

  Future<void> _confirmDelete(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Item delete karein?'),
            content: Text('${item['name']} menu se hata dein?'),
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
    await DatabaseHelper.instance.deleteMenuItem((item['id'] as num).toInt());
    _refreshMenu();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Menu Settings 📜')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _menuItems.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Menu abhi khali hai.\nNeeche + button se item add karo, fir vo har room me one-tap shortcut ki tarah dikhega.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _menuItems.length,
                  itemBuilder: (ctx, i) {
                    final item = _menuItems[i];
                    final price = (item['price'] as num?)?.toInt() ?? 0;
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      child: ListTile(
                        onTap: () => _showItemDialog(item: item),
                        leading: Text(item['icon']?.toString() ?? '🍽️',
                            style: const TextStyle(fontSize: 24)),
                        title: Text(item['name']?.toString() ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(AppHelpers.formatRupees(price)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              tooltip: 'Edit',
                              onPressed: () => _showItemDialog(item: item),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              tooltip: 'Delete',
                              onPressed: () => _confirmDelete(item),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showItemDialog(),
        tooltip: 'Naya item',
        child: const Icon(Icons.add),
      ),
    );
  }
}
