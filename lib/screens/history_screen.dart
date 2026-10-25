import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/database_helper.dart';
import '../utils/helpers.dart';

/// Checkout ho chuke rooms ka purana hisaab.
/// (Pehle checkout = seedha delete tha, record kabhi wapas nahi milta tha.)
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _checkouts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final data = await DatabaseHelper.instance.getCheckouts();
    if (!mounted) return;
    setState(() {
      _checkouts = data;
      _isLoading = false;
    });
  }

  List<dynamic> _parseItems(Map<String, dynamic> checkout) {
    try {
      final raw = checkout['items_json']?.toString();
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : [];
    } catch (_) {
      return [];
    }
  }

  Future<void> _showDetails(Map<String, dynamic> checkout) async {
    final items = _parseItems(checkout);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${checkout['room_name'] ?? 'Sir'}'),
        content: SizedBox(
          width: double.maxFinite,
          child: items.isEmpty
              ? const Text('Is checkout ki item detail uplabdh nahi hai.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (_, idx) {
                    final item = items[idx] as Map<String, dynamic>;
                    final isCredit = item['is_advance'] == 1;
                    final amt = (item['amount'] as num?)?.toInt() ?? 0;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(item['title']?.toString() ?? ''),
                      subtitle: Text(AppHelpers.formatDateTime(
                          item['date']?.toString())),
                      trailing: Text(
                        isCredit
                            ? '- ${AppHelpers.formatRupees(amt)}'
                            : AppHelpers.formatRupees(amt),
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isCredit ? Colors.green : Colors.red),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('BAND KARO')),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(Map<String, dynamic> checkout) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('History record delete karein?'),
            content: Text(
                '${checkout['room_name'] ?? 'Room'} ka ye purana hisaab hamesha ke liye delete ho jayega.'),
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
        .deleteCheckout((checkout['id'] as num).toInt());
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout History 🧾')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _checkouts.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Abhi tak koi checkout history nahi hai.\nJab kisi room ka Checkout (🧹) karoge, uska hisaab yahan safe save ho jayega.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    itemCount: _checkouts.length,
                    itemBuilder: (ctx, i) {
                      final c = _checkouts[i];
                      final expense =
                          (c['total_expense'] as num?)?.toInt() ?? 0;
                      final paid = (c['total_paid'] as num?)?.toInt() ?? 0;
                      final due = (c['balance_due'] as num?)?.toInt() ?? 0;
                      final itemCount = _parseItems(c).length;
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        child: ListTile(
                          onTap: () => _showDetails(c),
                          leading: CircleAvatar(
                            child: Text(
                              (c['room_name']?.toString().isNotEmpty ?? false)
                                  ? c['room_name'].toString()[0].toUpperCase()
                                  : 'S',
                            ),
                          ),
                          title: Text(
                            c['room_name']?.toString() ?? 'Sir',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '${AppHelpers.formatDateTime(c['checkout_date']?.toString())} • $itemCount items\n'
                            'Bill ${AppHelpers.formatRupees(expense)} | Jama ${AppHelpers.formatRupees(paid)}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                AppHelpers.formatRupees(due),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: due > 0 ? Colors.red : Colors.green,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red),
                                tooltip: 'Record delete',
                                onPressed: () => _confirmDelete(c),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
