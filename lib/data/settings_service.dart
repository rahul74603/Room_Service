import 'package:shared_preferences/shared_preferences.dart';

/// App ki settings (Settings screen se badli jati hain).
class AppSettings {
  final String hotelName; // Bill ke upar dikhne wala hotel/mess ka naam
  final int washingDailyRate; // Dhulai: per din rate (₹)
  final int washingMonthlyAmount; // Dhulai: pure mahine ka amount (₹)

  const AppSettings({
    this.hotelName = '',
    this.washingDailyRate = 70,
    this.washingMonthlyAmount = 2000,
  });
}

class SettingsService {
  static const String _keyHotelName = 'hotel_name';
  static const String _keyDailyRate = 'washing_daily_rate';
  static const String _keyMonthly = 'washing_monthly_amount';

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      hotelName: prefs.getString(_keyHotelName) ?? '',
      washingDailyRate: prefs.getInt(_keyDailyRate) ?? 70,
      washingMonthlyAmount: prefs.getInt(_keyMonthly) ?? 2000,
    );
  }

  static Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyHotelName, settings.hotelName.trim());
    await prefs.setInt(_keyDailyRate, settings.washingDailyRate);
    await prefs.setInt(_keyMonthly, settings.washingMonthlyAmount);
  }
}
