import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;

const String kDefaultEspBaseUrl = String.fromEnvironment(
  'ESP_BASE_URL',
  defaultValue: 'http://192.168.4.1',
);
const String kOpenAiApiKey = String.fromEnvironment(
  'OPENAI_API_KEY',
  defaultValue: '',
);
const Duration kSensorRefreshInterval = Duration(seconds: 7);
const double kDefaultSpeechRate = 0.45;

const Map<String, int> kSoilThresholds = {
  'Sandy': 500,
  'Loamy': 600,
  'Clay': 700,
};

enum AppLanguage { en, hi, bn }

String applyTemplate(String template, Map<String, String> values) {
  var output = template;
  values.forEach((token, value) {
    output = output.replaceAll('{$token}', value);
  });
  return output;
}

class CropProfile {
  const CropProfile({
    required this.name,
    required this.category,
    required this.waterMinMmPerWeek,
    required this.waterMaxMmPerWeek,
    required this.description,
  });

  final String name;
  final String category;
  final int waterMinMmPerWeek;
  final int waterMaxMmPerWeek;
  final String description;
}

const List<CropProfile> kCropProfiles = [
  CropProfile(
    name: 'Rice',
    category: 'Food Crop',
    waterMinMmPerWeek: 40,
    waterMaxMmPerWeek: 70,
    description: 'Needs standing water in many stages and stable irrigation.',
  ),
  CropProfile(
    name: 'Wheat',
    category: 'Food Crop',
    waterMinMmPerWeek: 25,
    waterMaxMmPerWeek: 40,
    description: 'Needs moderate watering and good drainage near maturity.',
  ),
  CropProfile(
    name: 'Maize',
    category: 'Food Crop',
    waterMinMmPerWeek: 30,
    waterMaxMmPerWeek: 45,
    description: 'Needs regular irrigation in tasseling and grain filling stages.',
  ),
  CropProfile(
    name: 'Millet',
    category: 'Food Crop',
    waterMinMmPerWeek: 15,
    waterMaxMmPerWeek: 25,
    description: 'Drought tolerant and suitable for low rainfall areas.',
  ),
  CropProfile(
    name: 'Pulses',
    category: 'Food Crop',
    waterMinMmPerWeek: 15,
    waterMaxMmPerWeek: 30,
    description: 'Light and controlled irrigation is generally enough.',
  ),
  CropProfile(
    name: 'Potato',
    category: 'Food Crop',
    waterMinMmPerWeek: 25,
    waterMaxMmPerWeek: 40,
    description: 'Needs frequent moisture during tuber development.',
  ),
  CropProfile(
    name: 'Tomato',
    category: 'Vegetable Crop',
    waterMinMmPerWeek: 20,
    waterMaxMmPerWeek: 35,
    description: 'Needs even watering to avoid fruit cracking.',
  ),
  CropProfile(
    name: 'Onion',
    category: 'Vegetable Crop',
    waterMinMmPerWeek: 20,
    waterMaxMmPerWeek: 30,
    description: 'Needs moderate watering and lower watering before harvest.',
  ),
  CropProfile(
    name: 'Brinjal',
    category: 'Vegetable Crop',
    waterMinMmPerWeek: 25,
    waterMaxMmPerWeek: 35,
    description: 'Needs regular moisture for fruit setting.',
  ),
  CropProfile(
    name: 'Cabbage',
    category: 'Vegetable Crop',
    waterMinMmPerWeek: 20,
    waterMaxMmPerWeek: 35,
    description: 'Needs consistent moisture for tight head formation.',
  ),
  CropProfile(
    name: 'Chilli',
    category: 'Vegetable Crop',
    waterMinMmPerWeek: 20,
    waterMaxMmPerWeek: 30,
    description: 'Needs controlled irrigation; avoid waterlogging.',
  ),
  CropProfile(
    name: 'Banana',
    category: 'Fruit Crop',
    waterMinMmPerWeek: 35,
    waterMaxMmPerWeek: 60,
    description: 'Needs high water and frequent irrigation.',
  ),
  CropProfile(
    name: 'Mango',
    category: 'Fruit Crop',
    waterMinMmPerWeek: 20,
    waterMaxMmPerWeek: 35,
    description: 'Needs light irrigation in flowering and fruiting stages.',
  ),
  CropProfile(
    name: 'Guava',
    category: 'Fruit Crop',
    waterMinMmPerWeek: 20,
    waterMaxMmPerWeek: 35,
    description: 'Needs balanced watering and good drainage.',
  ),
  CropProfile(
    name: 'Papaya',
    category: 'Fruit Crop',
    waterMinMmPerWeek: 25,
    waterMaxMmPerWeek: 40,
    description: 'Needs regular moisture for continuous fruiting.',
  ),
  CropProfile(
    name: 'Orange',
    category: 'Fruit Crop',
    waterMinMmPerWeek: 20,
    waterMaxMmPerWeek: 35,
    description: 'Needs deep watering and mulching around root zone.',
  ),
  CropProfile(
    name: 'Grapes',
    category: 'Fruit Crop',
    waterMinMmPerWeek: 20,
    waterMaxMmPerWeek: 35,
    description: 'Needs stage-based watering and careful canopy management.',
  ),
  CropProfile(
    name: 'Sugarcane',
    category: 'Cash Crop',
    waterMinMmPerWeek: 35,
    waterMaxMmPerWeek: 55,
    description: 'Long duration crop with high water demand.',
  ),
  CropProfile(
    name: 'Cotton',
    category: 'Cash Crop',
    waterMinMmPerWeek: 20,
    waterMaxMmPerWeek: 35,
    description: 'Needs moderate irrigation and dry weather at picking.',
  ),
  CropProfile(
    name: 'Groundnut',
    category: 'Oilseed Crop',
    waterMinMmPerWeek: 20,
    waterMaxMmPerWeek: 30,
    description: 'Needs irrigation at flowering and pegging stages.',
  ),
  CropProfile(
    name: 'Mustard',
    category: 'Oilseed Crop',
    waterMinMmPerWeek: 15,
    waterMaxMmPerWeek: 25,
    description: 'Needs limited water and good winter field moisture.',
  ),
  CropProfile(
    name: 'Sesame',
    category: 'Oilseed Crop',
    waterMinMmPerWeek: 10,
    waterMaxMmPerWeek: 20,
    description: 'Low water crop; avoid excess irrigation.',
  ),
  CropProfile(
    name: 'Tea',
    category: 'Plantation Crop',
    waterMinMmPerWeek: 30,
    waterMaxMmPerWeek: 45,
    description: 'Needs regular moisture and shade management.',
  ),
  CropProfile(
    name: 'Coffee',
    category: 'Plantation Crop',
    waterMinMmPerWeek: 25,
    waterMaxMmPerWeek: 40,
    description: 'Needs pre-blossom and blossom irrigation support.',
  ),
  CropProfile(
    name: 'Coconut',
    category: 'Plantation Crop',
    waterMinMmPerWeek: 30,
    waterMaxMmPerWeek: 45,
    description: 'Needs basin irrigation and mulch for retention.',
  ),
  CropProfile(
    name: 'Arecanut',
    category: 'Plantation Crop',
    waterMinMmPerWeek: 30,
    waterMaxMmPerWeek: 45,
    description: 'Needs consistent moisture in root zone.',
  ),
  CropProfile(
    name: 'Rubber',
    category: 'Plantation Crop',
    waterMinMmPerWeek: 25,
    waterMaxMmPerWeek: 40,
    description: 'Needs moisture support in dry months.',
  ),
];

const Map<String, int> kCropAdjustments = {
  'Rice': 50,
  'Wheat': -30,
  'Vegetables': 0,
  'Tomato': 0,
  'Maize': 0,
  'Banana': 30,
  'Mango': -10,
  'Sugarcane': 20,
  'Cotton': -5,
};

void main() {
  runApp(const SaswatAgroApp());
}

// ─── Design constants ──────────────────────────────────────────────────────
const Color kColorPrimary = Color(0xFF0D6E4A);
const Color kColorPrimaryLight = Color(0xFF10B981);
const Color kColorSecondary = Color(0xFF1D4ED8);
const Color kColorBackground = Color(0xFFF0F7F4);
const Color kColorSurface = Color(0xFFFFFFFF);
const Color kColorError = Color(0xFFDC2626);
const Color kColorWarning = Color(0xFFF59E0B);
const Color kColorInfo = Color(0xFF0EA5E9);
const LinearGradient kGradientPrimary = LinearGradient(
  colors: [Color(0xFF064E3B), Color(0xFF059669)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);
const LinearGradient kGradientWater = LinearGradient(
  colors: [Color(0xFF1E40AF), Color(0xFF3B82F6)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);
// ───────────────────────────────────────────────────────────────────────────

class SaswatAgroApp extends StatelessWidget {
  const SaswatAgroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Saswat Agro',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kColorPrimary,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: kColorBackground,
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          color: kColorSurface,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF1F5F9),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kColorPrimary, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: kColorPrimary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: kColorSurface,
          indicatorColor: kColorPrimary.withOpacity(0.15),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: kColorPrimary);
            }
            return const IconThemeData(color: Color(0xFF94A3B8));
          }),
        ),
      ),
      home: const SmartIrrigationShell(),
    );
  }
}

class SmartIrrigationShell extends StatefulWidget {
  const SmartIrrigationShell({super.key});

  @override
  State<SmartIrrigationShell> createState() => _SmartIrrigationShellState();
}

class _SmartIrrigationShellState extends State<SmartIrrigationShell> {
  final List<ChatMessage> _messages = [
    const ChatMessage(
      text:
          'Welcome to Saswat Agro. I can help with crops, irrigation, rainfall, and farm planning.',
      isUser: false,
    ),
  ];

  final stt.SpeechToText _speechToText = stt.SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();

  int _currentIndex = 0;
  AppLanguage _language = AppLanguage.en;

  String _espBaseUrl = kDefaultEspBaseUrl;
  String _openAiApiKey = kOpenAiApiKey;

  String _selectedSoil = 'Loamy';
  String _selectedCrop = 'Wheat';
  String _rainLocation = '';
  String? _rainfallPrediction;

  int? _moisture;
  bool _motorOn = false;
  bool _autoControlEnabled = true;
  bool _voiceEnabled = true;
  bool _isListening = false;

  bool _isRefreshing = false;
  bool _isMotorBusy = false;
  bool _isSendingSettings = false;
  bool _isChatLoading = false;
  bool _isRainLoading = false;

  String? _espError;
  DateTime? _lastUpdated;
  Timer? _refreshTimer;

  int get _threshold {
    final soilValue = kSoilThresholds[_selectedSoil] ?? 600;
    final cropValue = kCropAdjustments[_selectedCrop] ?? 0;
    return soilValue + cropValue;
  }

  bool get _isDry => _moisture != null && _moisture! > _threshold;

  CropProfile get _selectedCropProfile {
    return kCropProfiles.firstWhere(
      (item) => item.name == _selectedCrop,
      orElse: () => kCropProfiles.first,
    );
  }

  @override
  void initState() {
    super.initState();
    _initVoice();
    _refreshMoistureData(showLoader: true);
    _refreshTimer = Timer.periodic(kSensorRefreshInterval, (_) {
      _refreshMoistureData();
    });
  }

  Future<void> _initVoice() async {
    await _flutterTts.setSpeechRate(kDefaultSpeechRate);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _flutterTts.stop();
    super.dispose();
  }

  Map<String, String> _t(AppLanguage language) {
    switch (language) {
      case AppLanguage.hi:
        return {
          'appTitle': 'सास्वत एग्रो',
          'dashboard': 'डैशबोर्ड',
          'settings': 'सेटिंग्स',
          'advisory': 'सलाह',
          'chatbot': 'वॉइस चैटबॉट',
          'rain': 'बारिश अनुमान',
          'soilDry': 'मिट्टी सूखी है',
          'soilWet': 'मिट्टी गीली है',
          'noData': 'डेटा नहीं',
          'speakNow': 'अब बोलें...',
          'locationHint': 'गाँव/क्षेत्र का नाम लिखें या बोलें',
          'predictRain': 'बारिश अनुमान देखें',
          'home': 'होम',
          'soilLabel': 'मिट्टी',
          'cropLabel': 'फसल',
          'moistureLabel': 'नमी',
          'waterNeed': 'पानी की आवश्यकता',
          'threshold': 'सीमा',
          'updated': 'अपडेट',
          'refreshMoistureData': 'नमी डेटा रिफ्रेश करें',
          'motorOn': 'मोटर चालू',
          'motorOff': 'मोटर बंद',
          'autoMotorControl': 'ऑटो मोटर नियंत्रण',
          'autoMotorControlSubtitle': 'नमी के आधार पर मोटर को स्वचालित रूप से नियंत्रित करें।',
          'settingsIntro':
              'सास्वत एग्रो खाद्य, फल, बागान, सब्जी और अन्य फसलों का समर्थन करता है।\nESP डिवाइस कनेक्शन अपडेट करने के लिए ऐप सेटअप का उपयोग करें।',
          'selectSoil': 'मिट्टी चुनें',
          'chooseSoilType': 'मिट्टी का प्रकार चुनें',
          'selectCrop': 'फसल चुनें',
          'chooseCrop': 'फसल चुनें',
          'thresholdPreview': 'सीमा पूर्वावलोकन',
          'cropsCount': 'फसलें',
          'sendToEsp': 'ESP8266 पर भेजें',
          'askSimpleLanguage': 'सरल भाषा में पूछें...',
          'voiceInput': 'वॉइस इनपुट',
          'thinking': 'सोच रहा है...',
          'voiceLocation': 'वॉइस लोकेशन',
          'appSetup': 'ऐप सेटअप',
          'espBaseUrl': 'ESP8266 बेस URL',
          'language': 'भाषा',
          'enableVoiceOutput': 'वॉइस आउटपुट सक्षम करें',
          'saveSettings': 'सेटिंग्स सहेजें',
          'espNotConnected': 'ESP8266 कनेक्ट नहीं है। WiFi, IP और पावर जांचें।',
          'couldNotConnectEsp': 'ESP8266 से कनेक्ट नहीं हो सका।',
          'unableControlMotor': 'मोटर नियंत्रित नहीं हो सकी।',
          'settingsSent': 'सेटिंग्स ESP8266 को भेज दी गईं।',
          'failedSendSettings': 'सेटिंग्स भेजना विफल रहा।',
          'voiceInputUnavailable': 'वॉइस इनपुट उपलब्ध नहीं है।',
          'addApiKeyFirst': 'पहले सेटअप से अपना OpenAI API Key जोड़ें।',
          'couldNotProcess': 'मैं इसे प्रोसेस नहीं कर सका।',
          'requestFailedApi': 'अनुरोध विफल। API key और नेटवर्क जांचें।',
          'rainOutlookLow': 'कम बारिश की संभावना। सिंचाई की योजना बनाएं।',
          'rainOutlookModerate': 'मध्यम बारिश की संभावना।',
          'rainOutlookHigh': 'अधिक बारिश की संभावना। सिंचाई कम करें।',
          'rainPredictionOutput':
              '{location}: अगले 7 दिनों के लिए डेमो अनुमान: ~{rainMm} मिमी बारिश। {outlook}',
          'notSynced': 'सिंक नहीं हुआ',
          'irrigationDecision': 'सिंचाई निर्णय',
          'fieldDryAdvice': 'खेत सूखा लग रहा है। सिंचाई शुरू करें और नमी में कमी देखें।',
          'fieldWetAdvice': 'खेत में अभी पर्याप्त नमी है। अतिरिक्त सिंचाई से बचें।',
          'soilGuidanceTitle': '{soil} मिट्टी मार्गदर्शन',
          'sandyAdvice':
              'रेतीली मिट्टी से पानी जल्दी निकलता है। कम मात्रा में बार-बार सिंचाई और मल्चिंग करें।',
          'loamyAdvice':
              'दोमट मिट्टी संतुलित होती है। अंतराल पर गहरी सिंचाई आमतौर पर बेहतर रहती है।',
          'clayAdvice':
              'चिकनी मिट्टी पानी लंबे समय तक रोकती है। धीरे सिंचाई करें और पानी जमा न होने दें।',
          'sensorInsight': 'सेंसर जानकारी',
          'moistureUnavailable': 'लाइव नमी डेटा उपलब्ध नहीं है। ESP8266 कनेक्ट होने पर रिफ्रेश करें।',
          'moistureSummary': 'नमी {moisture} है और सीमा {threshold} है।',
        };
      case AppLanguage.bn:
        return {
          'appTitle': 'সাসওয়াত অ্যাগ্রো',
          'dashboard': 'ড্যাশবোর্ড',
          'settings': 'সেটিংস',
          'advisory': 'পরামর্শ',
          'chatbot': 'ভয়েস চ্যাটবট',
          'rain': 'বৃষ্টি পূর্বাভাস',
          'soilDry': 'মাটি শুকনো',
          'soilWet': 'মাটি ভেজা',
          'noData': 'ডেটা নেই',
          'speakNow': 'এখন বলুন...',
          'locationHint': 'এলাকার নাম লিখুন বা বলুন',
          'predictRain': 'বৃষ্টি পূর্বাভাস দেখুন',
          'home': 'হোম',
          'soilLabel': 'মাটি',
          'cropLabel': 'ফসল',
          'moistureLabel': 'আর্দ্রতা',
          'waterNeed': 'জলের প্রয়োজন',
          'threshold': 'থ্রেশহোল্ড',
          'updated': 'আপডেট',
          'refreshMoistureData': 'আর্দ্রতার ডেটা রিফ্রেশ করুন',
          'motorOn': 'মোটর চালু',
          'motorOff': 'মোটর বন্ধ',
          'autoMotorControl': 'অটো মোটর নিয়ন্ত্রণ',
          'autoMotorControlSubtitle': 'আর্দ্রতার ভিত্তিতে মোটর স্বয়ংক্রিয়ভাবে নিয়ন্ত্রণ করুন।',
          'settingsIntro':
              'সাসওয়াত অ্যাগ্রো খাদ্য, ফল, বাগান, সবজি এবং আরও অনেক ফসল সমর্থন করে।\nESP ডিভাইস সংযোগ আপডেট করতে অ্যাপ সেটআপ ব্যবহার করুন।',
          'selectSoil': 'মাটি নির্বাচন করুন',
          'chooseSoilType': 'মাটির ধরন নির্বাচন করুন',
          'selectCrop': 'ফসল নির্বাচন করুন',
          'chooseCrop': 'ফসল নির্বাচন করুন',
          'thresholdPreview': 'থ্রেশহোল্ড প্রিভিউ',
          'cropsCount': 'ফসল',
          'sendToEsp': 'ESP8266-এ পাঠান',
          'askSimpleLanguage': 'সহজ ভাষায় জিজ্ঞাসা করুন...',
          'voiceInput': 'ভয়েস ইনপুট',
          'thinking': 'ভাবছে...',
          'voiceLocation': 'ভয়েস লোকেশন',
          'appSetup': 'অ্যাপ সেটআপ',
          'espBaseUrl': 'ESP8266 বেস URL',
          'language': 'ভাষা',
          'enableVoiceOutput': 'ভয়েস আউটপুট চালু করুন',
          'saveSettings': 'সেটিংস সংরক্ষণ করুন',
          'espNotConnected': 'ESP8266 সংযুক্ত নয়। WiFi, IP এবং পাওয়ার পরীক্ষা করুন।',
          'couldNotConnectEsp': 'ESP8266-এ সংযোগ করা যায়নি।',
          'unableControlMotor': 'মোটর নিয়ন্ত্রণ করা যায়নি।',
          'settingsSent': 'সেটিংস ESP8266-এ পাঠানো হয়েছে।',
          'failedSendSettings': 'সেটিংস পাঠাতে ব্যর্থ হয়েছে।',
          'voiceInputUnavailable': 'ভয়েস ইনপুট উপলব্ধ নয়।',
          'addApiKeyFirst': 'প্রথমে সেটআপ থেকে OpenAI API Key যোগ করুন।',
          'couldNotProcess': 'আমি এটি প্রক্রিয়া করতে পারিনি।',
          'requestFailedApi': 'অনুরোধ ব্যর্থ। API key এবং নেটওয়ার্ক পরীক্ষা করুন।',
          'rainOutlookLow': 'কম বৃষ্টির সম্ভাবনা। সেচ পরিকল্পনা করুন।',
          'rainOutlookModerate': 'মাঝারি বৃষ্টির সম্ভাবনা।',
          'rainOutlookHigh': 'বেশি বৃষ্টির সম্ভাবনা। সেচ কমান।',
          'rainPredictionOutput':
              '{location}: আগামী ৭ দিনের ডেমো পূর্বাভাস: ~{rainMm} মিমি বৃষ্টি। {outlook}',
          'notSynced': 'সিঙ্ক হয়নি',
          'irrigationDecision': 'সেচ সিদ্ধান্ত',
          'fieldDryAdvice': 'ক্ষেত শুকনো মনে হচ্ছে। সেচ শুরু করুন এবং আর্দ্রতা কমা পর্যবেক্ষণ করুন।',
          'fieldWetAdvice': 'ক্ষেতে এখন পর্যাপ্ত আর্দ্রতা আছে। অতিরিক্ত সেচ এড়িয়ে চলুন।',
          'soilGuidanceTitle': '{soil} মাটির নির্দেশনা',
          'sandyAdvice':
              'বেলে মাটি দ্রুত পানি ছাড়ে। অল্প পরিমাণে ঘন ঘন সেচ এবং মালচিং ব্যবহার করুন।',
          'loamyAdvice':
              'দোআঁশ মাটি ভারসাম্যপূর্ণ। নির্দিষ্ট বিরতিতে গভীর সেচ সাধারণত ভালো কাজ করে।',
          'clayAdvice':
              'এঁটেল মাটি বেশি সময় পানি ধরে রাখে। ধীরে সেচ দিন এবং জলাবদ্ধতা এড়িয়ে চলুন।',
          'sensorInsight': 'সেন্সর তথ্য',
          'moistureUnavailable':
              'লাইভ আর্দ্রতার ডেটা নেই। ESP8266 সংযুক্ত হলে রিফ্রেশ করুন।',
          'moistureSummary': 'আর্দ্রতা {moisture} এবং থ্রেশহোল্ড {threshold}।',
        };
      case AppLanguage.en:
        return {
          'appTitle': 'Saswat Agro',
          'dashboard': 'Dashboard',
          'settings': 'Settings',
          'advisory': 'Advisory',
          'chatbot': 'Voice Chatbot',
          'rain': 'Rainfall Prediction',
          'soilDry': 'Soil is dry',
          'soilWet': 'Soil is wet',
          'noData': 'No data',
          'speakNow': 'Speak now...',
          'locationHint': 'Type or speak village/area location',
          'predictRain': 'Get rainfall prediction',
          'home': 'Home',
          'soilLabel': 'Soil',
          'cropLabel': 'Crop',
          'moistureLabel': 'Moisture',
          'waterNeed': 'Water need',
          'threshold': 'Threshold',
          'updated': 'Updated',
          'refreshMoistureData': 'Refresh moisture data',
          'motorOn': 'Motor ON',
          'motorOff': 'Motor OFF',
          'autoMotorControl': 'Auto motor control',
          'autoMotorControlSubtitle': 'Automatically control motor from moisture.',
          'settingsIntro':
              'Saswat Agro supports food crops, fruit crops, plantation crops, vegetable crops and more.\nUse app setup to update ESP device connection.',
          'selectSoil': 'Select Soil',
          'chooseSoilType': 'Choose soil type',
          'selectCrop': 'Select Crop',
          'chooseCrop': 'Choose crop',
          'thresholdPreview': 'Threshold preview',
          'cropsCount': 'crops',
          'sendToEsp': 'Send to ESP8266',
          'askSimpleLanguage': 'Ask in simple language...',
          'voiceInput': 'Voice input',
          'thinking': 'Thinking...',
          'voiceLocation': 'Voice location',
          'appSetup': 'App Setup',
          'espBaseUrl': 'ESP8266 Base URL',
          'language': 'Language',
          'enableVoiceOutput': 'Enable voice output',
          'saveSettings': 'Save settings',
          'espNotConnected': 'ESP8266 not connected. Check WiFi, IP, and power.',
          'couldNotConnectEsp': 'Could not connect to ESP8266.',
          'unableControlMotor': 'Unable to control motor.',
          'settingsSent': 'Settings sent to ESP8266.',
          'failedSendSettings': 'Failed to send settings.',
          'voiceInputUnavailable': 'Voice input not available.',
          'addApiKeyFirst': 'Add your OpenAI API key from setup first.',
          'couldNotProcess': 'I could not process that.',
          'requestFailedApi': 'Request failed. Verify API key and network.',
          'rainOutlookLow': 'Low rainfall expected. Plan irrigation.',
          'rainOutlookModerate': 'Moderate rainfall expected.',
          'rainOutlookHigh': 'High rainfall expected. Reduce irrigation.',
          'rainPredictionOutput':
              '{location}: Demo prediction for next 7 days: ~{rainMm} mm rain. {outlook}',
          'notSynced': 'Not synced',
          'irrigationDecision': 'Irrigation Decision',
          'fieldDryAdvice': 'Field appears dry. Start irrigation and monitor moisture reduction.',
          'fieldWetAdvice': 'Field has enough moisture now. Avoid extra watering.',
          'soilGuidanceTitle': '{soil} Soil Guidance',
          'sandyAdvice':
              'Sandy soil drains quickly. Use short and frequent irrigation cycles and mulching.',
          'loamyAdvice':
              'Loamy soil is balanced. Deep watering at intervals usually works best.',
          'clayAdvice':
              'Clay stores water longer. Irrigate slowly and avoid standing water.',
          'sensorInsight': 'Sensor Insight',
          'moistureUnavailable': 'Live moisture data unavailable. Refresh when ESP8266 is connected.',
          'moistureSummary': 'Moisture is {moisture} and threshold is {threshold}.',
        };
    }
  }

  String tr(String key) => _t(_language)[key] ?? key;

  String trf(String key, Map<String, String> values) {
    return applyTemplate(tr(key), values);
  }

  Uri _buildEspUri(String path, {Map<String, String>? queryParameters}) {
    final baseUri = Uri.parse(_espBaseUrl.trim());
    return baseUri.replace(
      path: path.startsWith('/') ? path : '/$path',
      queryParameters: queryParameters,
    );
  }

  Future<void> _refreshMoistureData({bool showLoader = false}) async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);

    try {
      final response =
          await http.get(_buildEspUri('/data')).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final moistureValue = _parseMoistureValue(utf8.decode(response.bodyBytes));

      if (!mounted) return;
      setState(() {
        _moisture = moistureValue;
        _espError = null;
        _lastUpdated = DateTime.now();
      });

      if (_autoControlEnabled) {
        await _applyAutomaticControl();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _espError = tr('espNotConnected');
      });
      if (showLoader) {
        _showSnackBar(tr('couldNotConnectEsp'), background: Colors.red);
      }
    } finally {
      if (!mounted) return;
      setState(() => _isRefreshing = false);
    }
  }

  int _parseMoistureValue(String body) {
    final trimmed = body.trim();
    final directValue = int.tryParse(trimmed);
    if (directValue != null) return directValue;

    final decoded = jsonDecode(trimmed);
    if (decoded is num) return decoded.toInt();

    if (decoded is Map) {
      for (final key in const ['moisture', 'value', 'sensor', 'data']) {
        final item = decoded[key];
        if (item is num) return item.toInt();
        final parsed = int.tryParse(item?.toString() ?? '');
        if (parsed != null) return parsed;
      }
    }
    throw const FormatException('Invalid moisture payload');
  }

  Future<void> _applyAutomaticControl() async {
    if (_moisture == null || _isMotorBusy) return;
    final shouldTurnOn = _isDry;
    if (_motorOn != shouldTurnOn) {
      await _setMotor(shouldTurnOn, silent: true);
    }
  }

  Future<void> _setMotor(bool turnOn, {bool silent = false}) async {
    if (_isMotorBusy) return;
    setState(() => _isMotorBusy = true);

    try {
      final response = await http
          .get(_buildEspUri(turnOn ? '/on' : '/off'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');

      if (!mounted) return;
      setState(() {
        _motorOn = turnOn;
        _espError = null;
      });
      if (!silent) _showSnackBar(turnOn ? tr('motorOn') : tr('motorOff'));
    } catch (_) {
      if (!mounted) return;
      setState(() => _espError = tr('unableControlMotor'));
      if (!silent) _showSnackBar(tr('unableControlMotor'), background: Colors.red);
    } finally {
      if (!mounted) return;
      setState(() => _isMotorBusy = false);
    }
  }

  Future<void> _applySettings(String soil, String crop) async {
    setState(() {
      _selectedSoil = soil;
      _selectedCrop = crop;
      _isSendingSettings = true;
    });

    try {
      final response = await http
          .get(_buildEspUri('/set', queryParameters: {'soil': soil, 'crop': crop}))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');

      if (!mounted) return;
      setState(() => _espError = null);
      _showSnackBar(tr('settingsSent'));
      await _refreshMoistureData();
    } catch (_) {
      if (!mounted) return;
      setState(() => _espError = tr('failedSendSettings'));
      _showSnackBar(tr('failedSendSettings'), background: Colors.red);
    } finally {
      if (!mounted) return;
      setState(() => _isSendingSettings = false);
    }
  }

  Future<void> _speak(String text) async {
    if (!_voiceEnabled) return;
    await _flutterTts.stop();
    await _flutterTts.speak(text);
  }

  Future<void> _startListening({
    required void Function(String text) onFinalText,
  }) async {
    final available = await _speechToText.initialize();
    if (!available) {
      _showSnackBar(tr('voiceInputUnavailable'), background: Colors.red);
      return;
    }
    setState(() => _isListening = true);
    await _speechToText.listen(
      onResult: (result) {
        if (result.finalResult) {
          onFinalText(result.recognizedWords);
        }
      },
      listenFor: const Duration(seconds: 12),
      pauseFor: const Duration(seconds: 3),
    );
    setState(() => _isListening = false);
  }

  Future<void> _sendChatMessage(String question) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty || _isChatLoading) return;

    setState(() {
      _messages.add(ChatMessage(text: trimmed, isUser: true));
      _isChatLoading = true;
    });

    try {
      final key = _openAiApiKey.trim();
      if (key.isEmpty) {
        throw Exception(tr('addApiKeyFirst'));
      }

      final crop = _selectedCropProfile;
      final prompt = '''
Farmer question:
$trimmed

Context:
- Soil: $_selectedSoil
- Crop: ${crop.name}
- Crop category: ${crop.category}
- Weekly water requirement: ${crop.waterMinMmPerWeek}-${crop.waterMaxMmPerWeek} mm
- Moisture reading: ${_moisture?.toString() ?? 'Unavailable'}
- Threshold: $_threshold
- Motor: ${_motorOn ? 'ON' : 'OFF'}

Respond in short and simple language suitable for farmers.
''';

      final response = await http
          .post(
            Uri.parse('https://api.openai.com/v1/responses'),
            headers: {
              'Authorization': 'Bearer $key',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': 'gpt-4.1-mini',
              'input': [
                {
                  'role': 'system',
                  'content': [
                    {
                      'type': 'input_text',
                      'text':
                          'You are Saswat Agro assistant. Give practical advice for irrigation, crops, weather, and disease in simple terms.',
                    },
                  ],
                },
                {
                  'role': 'user',
                  'content': [
                    {'type': 'input_text', 'text': prompt},
                  ],
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception(_extractApiError(utf8.decode(response.bodyBytes)));
      }

      final answer = _extractAssistantText(jsonDecode(utf8.decode(response.bodyBytes)));
      if (!mounted) return;

      setState(() {
        _messages.add(ChatMessage(text: answer, isUser: false));
      });
      await _speak(answer);
    } catch (error) {
      if (!mounted) return;
      final cleanError = error.toString().replaceFirst('Exception: ', '');
      setState(() {
        _messages.add(ChatMessage(
          text: '${tr('couldNotProcess')} $cleanError',
          isUser: false,
          isError: true,
        ));
      });
    } finally {
      if (!mounted) return;
      setState(() => _isChatLoading = false);
    }
  }

  String _extractApiError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        final message = (decoded['error'] as Map)['message'];
        if (message is String && message.isNotEmpty) return message;
      }
    } catch (_) {}
    return tr('requestFailedApi');
  }

  String _extractAssistantText(dynamic data) {
    if (data is Map) {
      final outputText = data['output_text'];
      if (outputText is String && outputText.trim().isNotEmpty) return outputText.trim();

      final output = data['output'];
      if (output is List) {
        for (final item in output) {
          if (item is Map && item['content'] is List) {
            for (final part in item['content'] as List) {
              if (part is Map) {
                final text = part['text'] ?? part['output_text'];
                if (text is String && text.trim().isNotEmpty) return text.trim();
              }
            }
          }
        }
      }
    }
    throw const FormatException('No AI text response found');
  }

  Future<void> _predictRainfall(String location) async {
    final trimmed = location.trim();
    if (trimmed.isEmpty || _isRainLoading) return;

    setState(() {
      _rainLocation = trimmed;
      _isRainLoading = true;
    });

    // Demo-only heuristic prediction based on location text.
    // Replace with a real weather API in production.
    final score = trimmed.toLowerCase().codeUnits.fold<int>(0, (sum, c) => sum + c);
    final rainMm = 20 + (score % 90);
    final outlook = rainMm < 35
        ? tr('rainOutlookLow')
        : rainMm < 65
            ? tr('rainOutlookModerate')
            : tr('rainOutlookHigh');

    final output = trf('rainPredictionOutput', {
      'location': trimmed,
      'rainMm': rainMm.toString(),
      'outlook': outlook,
    });
    if (!mounted) return;
    setState(() {
      _rainfallPrediction = output;
      _isRainLoading = false;
    });
    await _speak(output);
  }

  void _showSnackBar(String message, {Color background = const Color(0xFF0F5132)}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: background,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openConnectionSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return ConnectionSheet(
          initialEspBaseUrl: _espBaseUrl,
          initialOpenAiApiKey: _openAiApiKey,
          initialLanguage: _language,
          voiceEnabled: _voiceEnabled,
          tr: tr,
          onSave: (espBaseUrl, openAiApiKey, language, voiceEnabled) {
            setState(() {
              _espBaseUrl = espBaseUrl.trim();
              _openAiApiKey = openAiApiKey.trim();
              _language = language;
              _voiceEnabled = voiceEnabled;
            });
            Navigator.of(sheetContext).pop();
            _refreshMoistureData(showLoader: true);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pageTitles = [
      tr('dashboard'),
      tr('settings'),
      tr('advisory'),
      tr('chatbot'),
      tr('rain'),
    ];

    final pages = [
      DashboardScreen(
        tr: tr,
        moisture: _moisture,
        threshold: _threshold,
        motorOn: _motorOn,
        selectedSoil: _selectedSoil,
        selectedCrop: _selectedCrop,
        selectedCropProfile: _selectedCropProfile,
        isDry: _isDry,
        errorMessage: _espError,
        lastUpdated: _lastUpdated,
        isRefreshing: _isRefreshing,
        isMotorBusy: _isMotorBusy,
        autoControlEnabled: _autoControlEnabled,
        onRefresh: () => _refreshMoistureData(showLoader: true),
        onMotorToggle: _setMotor,
        onAutoControlChanged: (value) {
          setState(() => _autoControlEnabled = value);
          if (value) _applyAutomaticControl();
        },
      ),
      SettingsScreen(
        tr: tr,
        selectedSoil: _selectedSoil,
        selectedCrop: _selectedCrop,
        threshold: _threshold,
        isSending: _isSendingSettings,
        espBaseUrl: _espBaseUrl,
        onApply: _applySettings,
      ),
      AdvisoryScreen(
        tr: tr,
        selectedSoil: _selectedSoil,
        crop: _selectedCropProfile,
        moisture: _moisture,
        threshold: _threshold,
        isDry: _isDry,
      ),
      ChatbotScreen(
        tr: tr,
        messages: _messages,
        isLoading: _isChatLoading,
        selectedSoil: _selectedSoil,
        selectedCrop: _selectedCrop,
        moisture: _moisture,
        isListening: _isListening,
        onSend: _sendChatMessage,
        onVoicePressed: () => _startListening(
          onFinalText: (text) {
            if (text.trim().isEmpty) return;
            _sendChatMessage(text);
          },
        ),
      ),
      RainfallScreen(
        tr: tr,
        location: _rainLocation,
        prediction: _rainfallPrediction,
        isLoading: _isRainLoading,
        isListening: _isListening,
        onPredict: _predictRainfall,
        onVoiceLocation: () => _startListening(
          onFinalText: (text) {
            if (text.trim().isEmpty) return;
            _predictRainfall(text);
          },
        ),
      ),
    ];

    return Scaffold(
      backgroundColor: kColorBackground,
      body: Column(
        children: [
          _AppHeader(
            title: tr('appTitle'),
            subtitle: pageTitles[_currentIndex],
            isRefreshing: _isRefreshing,
            onRefresh: () => _refreshMoistureData(showLoader: true),
            onSettings: _openConnectionSheet,
          ),
          Expanded(
            child: IndexedStack(index: _currentIndex, children: pages),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: kColorSurface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: NavigationBar(
            height: 64,
            selectedIndex: _currentIndex,
            onDestinationSelected: (value) => setState(() => _currentIndex = value),
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.dashboard_outlined),
                selectedIcon: const Icon(Icons.dashboard_rounded),
                label: tr('home'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.tune_outlined),
                selectedIcon: const Icon(Icons.tune_rounded),
                label: tr('settings'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.eco_outlined),
                selectedIcon: const Icon(Icons.eco_rounded),
                label: tr('advisory'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                selectedIcon: const Icon(Icons.chat_bubble_rounded),
                label: tr('chatbot'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.cloud_outlined),
                selectedIcon: const Icon(Icons.cloud_rounded),
                label: tr('rain'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.tr,
    required this.moisture,
    required this.threshold,
    required this.motorOn,
    required this.selectedSoil,
    required this.selectedCrop,
    required this.selectedCropProfile,
    required this.isDry,
    required this.errorMessage,
    required this.lastUpdated,
    required this.isRefreshing,
    required this.isMotorBusy,
    required this.autoControlEnabled,
    required this.onRefresh,
    required this.onMotorToggle,
    required this.onAutoControlChanged,
  });

  final String Function(String) tr;
  final int? moisture;
  final int threshold;
  final bool motorOn;
  final String selectedSoil;
  final String selectedCrop;
  final CropProfile selectedCropProfile;
  final bool isDry;
  final String? errorMessage;
  final DateTime? lastUpdated;
  final bool isRefreshing;
  final bool isMotorBusy;
  final bool autoControlEnabled;
  final VoidCallback onRefresh;
  final ValueChanged<bool> onMotorToggle;
  final ValueChanged<bool> onAutoControlChanged;

  @override
  Widget build(BuildContext context) {
    // Scale the moisture bar so it fills at 1.5× threshold (wet), giving headroom.
    const double kMoistureBarScale = 1.5;
    final pct = moisture == null
        ? null
        : ((moisture! / (threshold * kMoistureBarScale)).clamp(0.0, 1.0));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      child: Column(
        children: [
          // ─── Hero moisture card ─────────────────────────────────────────
          _GradientCard(
            gradient: isDry ? kGradientWater : kGradientPrimary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        isDry ? Icons.water_drop_rounded : Icons.grass_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('moistureLabel'),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            moisture?.toString() ?? tr('noData'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isDry ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isDry ? tr('soilDry') : tr('soilWet'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Moisture bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 8,
                    backgroundColor: Colors.white.withOpacity(0.25),
                    valueColor: const AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _StatChip(
                      label: tr('threshold'),
                      value: threshold.toString(),
                    ),
                    const SizedBox(width: 8),
                    _StatChip(
                      label: tr('updated'),
                      value: formatTime(lastUpdated, tr('notSynced')),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ─── Crop & soil info ───────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _InfoCard(
                  icon: Icons.landscape_rounded,
                  iconColor: const Color(0xFF92400E),
                  iconBg: const Color(0xFFFEF3C7),
                  label: tr('soilLabel'),
                  value: selectedSoil,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _InfoCard(
                  icon: Icons.grass_rounded,
                  iconColor: const Color(0xFF166534),
                  iconBg: const Color(0xFFDCFCE7),
                  label: tr('cropLabel'),
                  value: selectedCrop,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: _InfoCard(
                  icon: Icons.water_rounded,
                  iconColor: const Color(0xFF1E40AF),
                  iconBg: const Color(0xFFDBEAFE),
                  label: tr('waterNeed'),
                  value:
                      '${selectedCropProfile.waterMinMmPerWeek}-${selectedCropProfile.waterMaxMmPerWeek} mm/w',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _InfoCard(
                  icon: Icons.settings_remote_rounded,
                  iconColor: motorOn ? const Color(0xFF166534) : const Color(0xFF6B7280),
                  iconBg: motorOn ? const Color(0xFFDCFCE7) : const Color(0xFFF3F4F6),
                  label: 'Motor',
                  value: motorOn ? tr('motorOn') : tr('motorOff'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ─── Motor control card ─────────────────────────────────────────
          _SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: kColorPrimary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.settings_remote_rounded, color: kColorPrimary),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Motor Control',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: tr('refreshMoistureData'),
                      onPressed: isRefreshing ? null : onRefresh,
                      icon: isRefreshing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, color: kColorPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        label: tr('motorOn'),
                        icon: Icons.power_settings_new_rounded,
                        color: kColorPrimary,
                        active: motorOn,
                        loading: isMotorBusy,
                        onPressed: isMotorBusy ? null : () => onMotorToggle(true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ActionButton(
                        label: tr('motorOff'),
                        icon: Icons.power_off_rounded,
                        color: kColorError,
                        active: !motorOn,
                        loading: isMotorBusy,
                        onPressed: isMotorBusy ? null : () => onMotorToggle(false),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (errorMessage != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: kColorError, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      errorMessage!,
                      style: const TextStyle(color: kColorError, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 10),

          // ─── Auto control toggle ────────────────────────────────────────
          _SurfaceCard(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: autoControlEnabled
                        ? kColorPrimary.withOpacity(0.1)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.auto_mode_rounded,
                    color: autoControlEnabled ? kColorPrimary : const Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('autoMotorControl'),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tr('autoMotorControlSubtitle'),
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: autoControlEnabled,
                  onChanged: onAutoControlChanged,
                  activeColor: kColorPrimary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.tr,
    required this.selectedSoil,
    required this.selectedCrop,
    required this.threshold,
    required this.isSending,
    required this.espBaseUrl,
    required this.onApply,
  });

  final String Function(String) tr;
  final String selectedSoil;
  final String selectedCrop;
  final int threshold;
  final bool isSending;
  final String espBaseUrl;
  final Future<void> Function(String soil, String crop) onApply;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late String _soil;
  late String _crop;

  @override
  void initState() {
    super.initState();
    _soil = widget.selectedSoil;
    _crop = widget.selectedCrop;
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedSoil != widget.selectedSoil ||
        oldWidget.selectedCrop != widget.selectedCrop) {
      _soil = widget.selectedSoil;
      _crop = widget.selectedCrop;
    }
  }

  @override
  Widget build(BuildContext context) {
    final previewThreshold =
        (kSoilThresholds[_soil] ?? 600) + (kCropAdjustments[_crop] ?? 0);
    final groups = groupByCategory(kCropProfiles);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Intro banner ───────────────────────────────────────────────
          _GradientCard(
            gradient: kGradientPrimary,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.settings_rounded, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    widget.tr('settingsIntro'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ─── Soil selection ─────────────────────────────────────────────
          _SectionLabel(label: widget.tr('selectSoil'), icon: Icons.landscape_rounded),
          const SizedBox(height: 8),
          _SurfaceCard(
            child: DropdownButtonFormField<String>(
              value: _soil,
              decoration: InputDecoration(
                hintText: widget.tr('chooseSoilType'),
                prefixIcon: const Icon(Icons.landscape_rounded, color: kColorPrimary),
              ),
              items: kSoilThresholds.keys
                  .map((soil) => DropdownMenuItem(value: soil, child: Text(soil)))
                  .toList(),
              onChanged: (value) => setState(() => _soil = value ?? _soil),
            ),
          ),

          const SizedBox(height: 16),

          // ─── Crop selection ─────────────────────────────────────────────
          _SectionLabel(label: widget.tr('selectCrop'), icon: Icons.grass_rounded),
          const SizedBox(height: 8),
          _SurfaceCard(
            child: DropdownButtonFormField<String>(
              value: _crop,
              isExpanded: true,
              decoration: InputDecoration(
                hintText: widget.tr('chooseCrop'),
                prefixIcon: const Icon(Icons.grass_rounded, color: kColorPrimary),
              ),
              items: kCropProfiles
                  .map((crop) => DropdownMenuItem(
                        value: crop.name,
                        child: Text('${crop.name} (${crop.category})'),
                      ))
                  .toList(),
              onChanged: (value) => setState(() => _crop = value ?? _crop),
            ),
          ),

          const SizedBox(height: 16),

          // ─── Threshold preview ──────────────────────────────────────────
          _SurfaceCard(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: kColorInfo.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.speed_rounded, color: kColorInfo, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.tr('thresholdPreview'),
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        previewThreshold.toString(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 24,
                          color: kColorPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: groups.entries
                      .map((e) => Text(
                            '${e.key}: ${e.value.length}',
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ─── Apply button ───────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: widget.isSending ? null : () => widget.onApply(_soil, _crop),
              icon: widget.isSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(
                widget.tr('sendToEsp'),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _buildDropdownDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF8FBFA),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }
}

class AdvisoryScreen extends StatelessWidget {
  const AdvisoryScreen({
    super.key,
    required this.tr,
    required this.selectedSoil,
    required this.crop,
    required this.moisture,
    required this.threshold,
    required this.isDry,
  });

  final String Function(String) tr;
  final String selectedSoil;
  final CropProfile crop;
  final int? moisture;
  final int threshold;
  final bool isDry;

  @override
  Widget build(BuildContext context) {
    final items = buildAdvisoryItems(
      soil: selectedSoil,
      crop: crop,
      moisture: moisture,
      isDry: isDry,
      irrigationDecisionTitle: tr('irrigationDecision'),
      fieldDryAdvice: tr('fieldDryAdvice'),
      fieldWetAdvice: tr('fieldWetAdvice'),
      soilGuidanceTitle: applyTemplate(tr('soilGuidanceTitle'), {'soil': selectedSoil}),
      soilAdvice: {
        'Sandy': tr('sandyAdvice'),
        'Loamy': tr('loamyAdvice'),
        'Clay': tr('clayAdvice'),
      },
      moistureUnavailable: tr('moistureUnavailable'),
      moistureSummary: applyTemplate(
        tr('moistureSummary'),
        {'moisture': (moisture ?? 0).toString(), 'threshold': threshold.toString()},
      ),
      sensorInsightTitle: tr('sensorInsight'),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      child: Column(
        children: items
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: kColorSurface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: item.color.withOpacity(0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            width: 6,
                            color: item.color,
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: item.color.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(item.icon, color: item.color, size: 22),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          item.description,
                                          style: const TextStyle(
                                            color: Color(0xFF475569),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            height: 1.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({
    super.key,
    required this.tr,
    required this.messages,
    required this.isLoading,
    required this.selectedSoil,
    required this.selectedCrop,
    required this.moisture,
    required this.isListening,
    required this.onSend,
    required this.onVoicePressed,
  });

  final String Function(String) tr;
  final List<ChatMessage> messages;
  final bool isLoading;
  final String selectedSoil;
  final String selectedCrop;
  final int? moisture;
  final bool isListening;
  final Future<void> Function(String question) onSend;
  final VoidCallback onVoicePressed;

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant ChatbotScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messages.length != widget.messages.length ||
        oldWidget.isLoading != widget.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.isLoading) return;
    _controller.clear();
    await widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
      child: Column(
        children: [
          // ─── Context chips ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: kColorSurface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _tag(
                    '${widget.tr('soilLabel')}: ${widget.selectedSoil}',
                    const Color(0xFFFEF3C7),
                    const Color(0xFF92400E),
                  ),
                  _tag(
                    '${widget.tr('cropLabel')}: ${widget.selectedCrop}',
                    const Color(0xFFDCFCE7),
                    const Color(0xFF166534),
                  ),
                  _tag(
                    '${widget.tr('moistureLabel')}: ${widget.moisture?.toString() ?? widget.tr('noData')}',
                    const Color(0xFFDBEAFE),
                    const Color(0xFF1E40AF),
                  ),
                  if (widget.isListening)
                    _tag(widget.tr('speakNow'), const Color(0xFFFCE7F3), const Color(0xFF9D174D)),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          // ─── Chat messages ──────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: kColorSurface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ListView.separated(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(14),
                  itemCount: widget.messages.length + (widget.isLoading ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    if (index >= widget.messages.length) {
                      return ChatBubble(
                          text: widget.tr('thinking'), isUser: false, isLoading: true);
                    }
                    final message = widget.messages[index];
                    return ChatBubble(
                      text: message.text,
                      isUser: message.isUser,
                      isError: message.isError,
                    );
                  },
                ),
              ),
            ),
          ),

          // ─── Input bar ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: kColorSurface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 16,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      onSubmitted: (_) => _handleSend(),
                      decoration: InputDecoration(
                        hintText: widget.tr('askSimpleLanguage'),
                        hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _CircleIconButton(
                    icon: widget.isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                    color: widget.isListening ? kColorError : const Color(0xFF94A3B8),
                    backgroundColor: widget.isListening
                        ? kColorError.withOpacity(0.1)
                        : const Color(0xFFF1F5F9),
                    onPressed: widget.isLoading ? null : widget.onVoicePressed,
                    tooltip: widget.tr('voiceInput'),
                  ),
                  const SizedBox(width: 6),
                  _CircleIconButton(
                    icon: Icons.send_rounded,
                    color: Colors.white,
                    backgroundColor: kColorPrimary,
                    onPressed: widget.isLoading ? null : _handleSend,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: TextStyle(fontWeight: FontWeight.w600, color: fg, fontSize: 12)),
    );
  }
}

class RainfallScreen extends StatefulWidget {
  const RainfallScreen({
    super.key,
    required this.tr,
    required this.location,
    required this.prediction,
    required this.isLoading,
    required this.isListening,
    required this.onPredict,
    required this.onVoiceLocation,
  });

  final String Function(String) tr;
  final String location;
  final String? prediction;
  final bool isLoading;
  final bool isListening;
  final Future<void> Function(String location) onPredict;
  final VoidCallback onVoiceLocation;

  @override
  State<RainfallScreen> createState() => _RainfallScreenState();
}

class _RainfallScreenState extends State<RainfallScreen> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.location);
  }

  @override
  void didUpdateWidget(covariant RainfallScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.location != _controller.text) {
      _controller.text = widget.location;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Hero card ──────────────────────────────────────────────────
          _GradientCard(
            gradient: kGradientWater,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.cloud_rounded, color: Colors.white, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.tr('rain'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.tr('locationHint'),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ─── Location input ─────────────────────────────────────────────
          _SurfaceCard(
            child: Column(
              children: [
                TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: widget.tr('locationHint'),
                    prefixIcon: const Icon(Icons.location_on_rounded, color: kColorPrimary),
                    suffixIcon: _CircleIconButton(
                      icon: widget.isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                      color: widget.isListening ? kColorError : const Color(0xFF64748B),
                      backgroundColor: widget.isListening
                          ? kColorError.withOpacity(0.1)
                          : const Color(0xFFF1F5F9),
                      onPressed: widget.isLoading ? null : widget.onVoiceLocation,
                      tooltip: widget.tr('voiceLocation'),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed:
                        widget.isLoading ? null : () => widget.onPredict(_controller.text),
                    icon: widget.isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.cloud_rounded),
                    label: Text(
                      widget.tr('predictRain'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ─── Prediction result ──────────────────────────────────────────
          if (widget.prediction != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF0EA5E9).withOpacity(0.08),
                    const Color(0xFF0EA5E9).withOpacity(0.02),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF0EA5E9).withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: kColorInfo.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.wb_cloudy_rounded, color: kColorInfo, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.prediction!,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Color(0xFF0C4A6E),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ConnectionSheet extends StatefulWidget {
  const ConnectionSheet({
    super.key,
    required this.initialEspBaseUrl,
    required this.initialOpenAiApiKey,
    required this.initialLanguage,
    required this.voiceEnabled,
    required this.tr,
    required this.onSave,
  });

  final String initialEspBaseUrl;
  final String initialOpenAiApiKey;
  final AppLanguage initialLanguage;
  final bool voiceEnabled;
  final String Function(String) tr;
  final void Function(
    String espBaseUrl,
    String openAiApiKey,
    AppLanguage language,
    bool voiceEnabled,
  ) onSave;

  @override
  State<ConnectionSheet> createState() => _ConnectionSheetState();
}

class _ConnectionSheetState extends State<ConnectionSheet> {
  late final TextEditingController _espController;
  late final TextEditingController _apiKeyController;
  AppLanguage _language = AppLanguage.en;
  late bool _voiceEnabled;

  @override
  void initState() {
    super.initState();
    _espController = TextEditingController(text: widget.initialEspBaseUrl);
    _apiKeyController = TextEditingController(text: widget.initialOpenAiApiKey);
    _language = widget.initialLanguage;
    _voiceEnabled = widget.voiceEnabled;
  }

  @override
  void dispose() {
    _espController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, bottomInset + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle + title
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: kColorPrimary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.settings_rounded, color: kColorPrimary),
              ),
              const SizedBox(width: 12),
              Text(
                widget.tr('appSetup'),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _espController,
            decoration: InputDecoration(
              labelText: widget.tr('espBaseUrl'),
              hintText: 'http://192.168.4.1',
              prefixIcon: const Icon(Icons.router_rounded, color: kColorPrimary),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKeyController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'OpenAI API Key',
              hintText: 'sk-...',
              prefixIcon: Icon(Icons.vpn_key_rounded, color: kColorPrimary),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<AppLanguage>(
            value: _language,
            decoration: InputDecoration(
              labelText: widget.tr('language'),
              prefixIcon: const Icon(Icons.language_rounded, color: kColorPrimary),
            ),
            items: const [
              DropdownMenuItem(value: AppLanguage.en, child: Text('English')),
              DropdownMenuItem(value: AppLanguage.hi, child: Text('Hindi')),
              DropdownMenuItem(value: AppLanguage.bn, child: Text('Bengali')),
            ],
            onChanged: (value) => setState(() => _language = value ?? AppLanguage.en),
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(14),
            ),
            child: SwitchListTile.adaptive(
              value: _voiceEnabled,
              onChanged: (v) => setState(() => _voiceEnabled = v),
              title: Text(
                widget.tr('enableVoiceOutput'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              activeColor: kColorPrimary,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: () => widget.onSave(
                _espController.text,
                _apiKeyController.text,
                _language,
                _voiceEnabled,
              ),
              icon: const Icon(Icons.save_rounded),
              label: Text(
                widget.tr('saveSettings'),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppHeader extends StatelessWidget {
  const _AppHeader({
    required this.title,
    required this.subtitle,
    required this.isRefreshing,
    required this.onRefresh,
    required this.onSettings,
  });

  final String title;
  final String subtitle;
  final bool isRefreshing;
  final VoidCallback onRefresh;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: kGradientPrimary),
      padding: EdgeInsets.fromLTRB(20, topPadding + 12, 16, 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.grass_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.75),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          _CircleIconButton(
            icon: isRefreshing ? Icons.hourglass_bottom_rounded : Icons.refresh_rounded,
            color: Colors.white,
            backgroundColor: Colors.white.withOpacity(0.2),
            onPressed: isRefreshing ? null : onRefresh,
          ),
          const SizedBox(width: 8),
          _CircleIconButton(
            icon: Icons.settings_rounded,
            color: Colors.white,
            backgroundColor: Colors.white.withOpacity(0.2),
            onPressed: onSettings,
          ),
        ],
      ),
    );
  }
}

class _GradientCard extends StatelessWidget {
  const _GradientCard({required this.child, required this.gradient});

  final Widget child;
  final LinearGradient gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: gradient.colors.last.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kColorSurface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kColorSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.active,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool active;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: active ? color : color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? color : color.withOpacity(0.2),
          ),
        ),
        child: Center(
          child: loading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: active ? Colors.white : color,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: active ? Colors.white : color, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        color: active ? Colors.white : color,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: kColorPrimary, size: 18),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.color,
    required this.backgroundColor,
    this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final Color color;
  final Color backgroundColor;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final btn = GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: btn);
    }
    return btn;
  }
}

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.text,
    required this.isUser,
    this.isError = false,
    this.isLoading = false,
  });

  final String text;
  final bool isUser;
  final bool isError;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: kGradientPrimary,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(4),
            ),
            boxShadow: [
              BoxShadow(
                color: kColorPrimary.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ),
      );
    }

    final isErr = isError;
    final bubbleBg = isErr ? const Color(0xFFFEF2F2) : const Color(0xFFF0F7F4);
    final textColor = isErr ? const Color(0xFF991B1B) : const Color(0xFF1E293B);
    final borderColor = isErr ? const Color(0xFFFCA5A5) : const Color(0xFFD1FAE5);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: bubbleBg,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(18),
          ),
          border: Border.all(color: borderColor),
        ),
        child: isLoading
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: kColorPrimary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    text,
                    style: TextStyle(color: textColor, fontSize: 14),
                  ),
                ],
              )
            : Text(
                text,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
      ),
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.text,
    required this.isUser,
    this.isError = false,
  });

  final String text;
  final bool isUser;
  final bool isError;
}

class AdviceItem {
  const AdviceItem({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color color;
}

List<AdviceItem> buildAdvisoryItems({
  required String soil,
  required CropProfile crop,
  required int? moisture,
  required bool isDry,
  required String irrigationDecisionTitle,
  required String fieldDryAdvice,
  required String fieldWetAdvice,
  required String soilGuidanceTitle,
  required Map<String, String> soilAdvice,
  required String moistureUnavailable,
  required String moistureSummary,
  required String sensorInsightTitle,
}) {
  final localizedMoistureSummary = moisture == null ? moistureUnavailable : moistureSummary;

  return [
    AdviceItem(
      title: irrigationDecisionTitle,
      description: isDry
          ? fieldDryAdvice
          : fieldWetAdvice,
      icon: Icons.water_drop,
      color: isDry ? const Color(0xFFD97706) : const Color(0xFF2563EB),
    ),
    AdviceItem(
      title: soilGuidanceTitle,
      description: soilAdvice[soil] ?? soilAdvice['Loamy']!,
      icon: Icons.landscape,
      color: const Color(0xFF14B8A6),
    ),
    AdviceItem(
      title: '${crop.name} (${crop.category})',
      description:
          '${crop.description} Weekly water target: ${crop.waterMinMmPerWeek}-${crop.waterMaxMmPerWeek} mm.',
      icon: Icons.grass,
      color: const Color(0xFF22C55E),
    ),
    AdviceItem(
      title: sensorInsightTitle,
      description: localizedMoistureSummary,
      icon: Icons.analytics,
      color: const Color(0xFF1D6FD8),
    ),
  ];
}

Map<String, List<CropProfile>> groupByCategory(List<CropProfile> crops) {
  final grouped = <String, List<CropProfile>>{};
  for (final crop in crops) {
    grouped.putIfAbsent(crop.category, () => []).add(crop);
  }
  return grouped;
}

String formatTime(DateTime? dateTime, String notSyncedLabel) {
  if (dateTime == null) return notSyncedLabel;
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final second = dateTime.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}
