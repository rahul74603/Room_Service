import 'package:flutter/material.dart';

import '../app_version.dart';
import '../data/settings_service.dart';
import '../main.dart';

/// Settings: bill par dikhne wala hotel/mess naam, dhulai ke rate, dark mode.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _hotelC = TextEditingController();
  final TextEditingController _dailyC = TextEditingController();
  final TextEditingController _monthlyC = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _hotelC.dispose();
    _dailyC.dispose();
    _monthlyC.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await SettingsService.load();
    if (!mounted) return;
    setState(() {
      _hotelC.text = s.hotelName;
      _dailyC.text = '${s.washingDailyRate}';
      _monthlyC.text = '${s.washingMonthlyAmount}';
      _loading = false;
    });
  }

  Future<void> _save() async {
    final daily = int.tryParse(_dailyC.text.trim()) ?? 0;
    final monthly = int.tryParse(_monthlyC.text.trim()) ?? 0;
    if (daily <= 0 || monthly <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Dhulai ke rate 0 se bade rakho'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    await SettingsService.save(AppSettings(
      hotelName: _hotelC.text.trim(),
      washingDailyRate: daily,
      washingMonthlyAmount: monthly,
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Settings save ho gayi ✅')));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings ⚙️')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Dark mode (pehle home ke upar button tha, ab yahan hai)
                Card(
                  child: SwitchListTile(
                    secondary:
                        Icon(isDark ? Icons.dark_mode : Icons.light_mode),
                    title: const Text('Dark Mode'),
                    value: isDark,
                    onChanged: (_) => MyApp.toggleTheme(context),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Bill par dikhne wala naam',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _hotelC,
                  decoration: const InputDecoration(
                    labelText: 'Hotel / Mess ka naam',
                    hintText: 'e.g. BSF Academy Tekanpur',
                    border: OutlineInputBorder(),
                    helperText:
                        'Ye naam PDF aur WhatsApp bill ke sabse upar dikhega. Khali chhoda to "HOTEL STATEMENT" aayega.',
                    helperMaxLines: 3,
                  ),
                ),
                const SizedBox(height: 24),
                const Text('Dhulai (Washing) ke rate',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _dailyC,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Per din (₹)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _monthlyC,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Pura mahina (₹)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Hisaab: har din per-day rate judta hai; pura mahina ho jaye to "pura mahina" wali rakam lagti hai. Mahina beet jaye aur bill na bana ho to app Pending dikhayega.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 28),
                ElevatedButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save),
                  label: const Text('SAVE KARO'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 24),
                const Center(
                  child: Text(
                    'RoomService Pro • Version $appVersion',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              ],
            ),
    );
  }
}
