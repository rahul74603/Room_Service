import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart'; 
import 'screens/home_screen.dart'; 

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
  
  static void toggleTheme(BuildContext context) {
    context.findAncestorStateOfType<_MyAppState>()?._toggleTheme();
  }
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  void _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    bool isDark = prefs.getBool('isDark') ?? false;
    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  void _toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
    prefs.setBool('isDark', _themeMode == ThemeMode.dark);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RoomService Pro',
      debugShowCheckedModeBanner: false,
      
      // ✨ LIGHT THEME
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF3F4F6),
        textTheme: GoogleFonts.poppinsTextTheme(),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(color: Colors.black, fontSize: 22, fontWeight: FontWeight.bold),
          iconTheme: IconThemeData(color: Colors.black),
        ),
        
        // 🔥 FIX 1: 'CardTheme' ko 'CardThemeData' nahi mil raha to hum seedha styling hatate hain
        // ya 'CardTheme' class agar data mang rahi hai to hum use manually set karte hain.
        // ERROR FIX: Hum yahan se 'cardTheme' hata rahe hain kyunki ye version mismatch kar raha hai.
        // Cards fir bhi sunder dikhenge kyunki humne home_screen me alag se design kiya hai.
        
        // cardTheme: const CardTheme(elevation: 5, color: Colors.white), // <--- REMOVED TO FIX ERROR
      ),
      
      // 🌙 DARK THEME
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD0BCFF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
        ),
        
        // 🔥 FIX 2: Dark theme se bhi 'cardTheme' hata diya.
        // cardTheme: const CardTheme(elevation: 5, color: Color(0xFF1E1E1E)), // <--- REMOVED TO FIX ERROR
      ),
      
      themeMode: _themeMode,
      home: HomeScreen(),
    );
  }
}