import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// ===============================================================
/// IoT-Based Smart Irrigation System with AI Chatbot
/// - ESP8266 via HTTP
/// - Crop + Soil threshold intelligence
/// - Advisory + OpenAI chatbot
/// ===============================================================

void main() {
  runApp(const SmartIrrigationApp());
}

/// ----------------------------
/// App-wide model/state (simple)
/// ----------------------------
class AppState extends ChangeNotifier {
  // ESP8266 base URL (update to your ESP IP)
  // Example: "http://192.168.4.1" or "http://192.168.1.50"
  String espBaseUrl = "http://192.168.4.1";

  // OpenAI API Key (set your key here OR load securely in production)
  String openAiApiKey = "PASTE_YOUR_OPENAI_API_KEY_HERE";

  // Selected soil & crop
  String soilType = "Loamy";
  String cropType = "Wheat";

  // Live sensor/motor data
  int? moisture;
  bool motorOn = false;

  // UI / networking state
  bool isFetching = false;
  String? lastError;

  // Auto mode: based on moisture threshold logic
  bool autoMode = true;

  // For dry-soil alert cooldown
  DateTime? _lastDryAlertAt;

  /// Threshold logic per requirement.
  int get soilBaseThreshold {
    switch (soilType) {
      case "Sandy":
        return 500;
      case "Loamy":
        return 600;
      case "Clay":
        return 700;
      default:
        return 600;
    }
  }

  int get cropAdjustment {
    switch (cropType) {
      case "Rice":
        return 50;
      case "Wheat":
        return -30;
      case "Vegetables":
        return 0;
      case "Tomato":
        // Not explicitly specified, treat as vegetables (0) or tweak if you want.
        return 0;
      default:
        return 0;
    }
  }

  int get finalThreshold => soilBaseThreshold + cropAdjustment;

  bool get isDry => (moisture != null) ? (moisture! > finalThreshold) : false;

  String get moistureStatusText {
    if (moisture == null) return "No Data";
    return isDry ? "Dry" : "Wet";
  }

  String get recommendationText {
    if (moisture == null) return "Connect to ESP8266 to get moisture data.";
    return isDry
        ? "Soil is dry → irrigation needed"
        : "Soil is wet → no irrigation required";
  }

  /// Advisory content (simple, practical)
  List<String> get advisoryBullets {
    final bullets = <String>[];

    // Soil-based guidance
    if (soilType == "Sandy") {
      bullets.add("Sandy soil drains fast; irrigate in shorter, more frequent cycles.");
      bullets.add("Add organic matter (compost) to improve water retention.");
    } else if (soilType == "Loamy") {
      bullets.add("Loamy soil is balanced; use moderate irrigation and monitor moisture trends.");
      bullets.add("Avoid watering at peak sun hours to reduce evaporation.");
    } else if (soilType == "Clay") {
      bullets.add("Clay soil holds water longer; avoid overwatering to prevent root rot.");
      bullets.add("Use slow irrigation so water can infiltrate without runoff.");
    }

    // Crop-based guidance
    if (cropType == "Rice") {
      bullets.add("Rice generally needs higher water availability; maintain consistent moisture.");
      bullets.add("Check for water stagnation issues and mosquito breeding in standing water.");
    } else if (cropType == "Wheat") {
      bullets.add("Wheat prefers controlled watering; avoid excess moisture during early growth.");
      bullets.add("Irrigate based on critical stages (tillering, flowering, grain filling).");
    } else if (cropType == "Vegetables" || cropType == "Tomato") {
      bullets.add("Vegetables need steady moisture; irregular watering can reduce quality.");
      bullets.add("Mulching helps retain moisture and reduces weed growth.");
      if (cropType == "Tomato") {
        bullets.add("For tomato, avoid wetting leaves to reduce fungal disease risk.");
      }
    }

    // Threshold rule summary
    bullets.add("Current threshold: $finalThreshold (Soil $soilBaseThreshold + Crop adj $cropAdjustment)");
    bullets.add(recommendationText);

    return bullets;
  }

  /// Update soil/crop locally
  void setSoil(String value) {
    soilType = value;
    notifyListeners();
  }

  void setCrop(String value) {
    cropType = value;
    notifyListeners();
  }

  void setEspBaseUrl(String value) {
    espBaseUrl = value.trim();
    notifyListeners();
  }

  void setAutoMode(bool value) {
    autoMode = value;
    notifyListeners();
  }

  /// Network: Fetch moisture data from ESP /data
  Future<void> fetchMoistureAndMaybeAutoControl() async {
    isFetching = true;
    lastError = null;
    notifyListeners();

    try {
      final url = Uri.parse("$espBaseUrl/data");
      final res = await http.get(url).timeout(const Duration(seconds: 3));

      if (res.statusCode != 200) {
        throw Exception("ESP returned HTTP ${res.statusCode}");
      }

      // Accept either plain number ("635") or JSON like {"moisture":635}
      final body = res.body.trim();
      int parsed;

      if (body.startsWith("{")) {
        final obj = jsonDecode(body);
        parsed = (obj["moisture"] as num).toInt();
      } else {
        parsed = int.parse(body);
      }

      moisture = parsed;

      // Apply intelligence for recommendation; optionally auto-control motor
      if (autoMode) {
        if (isDry) {
          await motorOnCommand(silent: true);
          _maybeTriggerDryAlertCooldown();
        } else {
          await motorOffCommand(silent: true);
        }
      } else {
        // Even in manual mode, still show alert suggestion (no forced motor action)
        if (isDry) _maybeTriggerDryAlertCooldown();
      }
    } on TimeoutException {
      lastError = "Connection timed out. Check WiFi and ESP IP.";
    } catch (e) {
      lastError = "Failed to fetch data. ${e.toString()}";
    } finally {
      isFetching = false;
      notifyListeners();
    }
  }

  Future<void> motorOnCommand({bool silent = false}) async {
    try {
      final url = Uri.parse("$espBaseUrl/on");
      final res = await http.get(url).timeout(const Duration(seconds: 3));
      if (res.statusCode != 200) {
        throw Exception("ESP returned HTTP ${res.statusCode}");
      }
      motorOn = true;
      lastError = null;
    } catch (e) {
      if (!silent) lastError = "Failed to turn motor ON. ${e.toString()}";
    } finally {
      notifyListeners();
    }
  }

  Future<void> motorOffCommand({bool silent = false}) async {
    try {
      final url = Uri.parse("$espBaseUrl/off");
      final res = await http.get(url).timeout(const Duration(seconds: 3));
      if (res.statusCode != 200) {
        throw Exception("ESP returned HTTP ${res.statusCode}");
      }
      motorOn = false;
      lastError = null;
    } catch (e) {
      if (!silent) lastError = "Failed to turn motor OFF. ${e.toString()}";
    } finally {
      notifyListeners();
    }
  }

  Future<void> sendSoilCropToEsp() async {
    isFetching = true;
    lastError = null;
    notifyListeners();

    try {
      final url = Uri.parse(
        "$espBaseUrl/set?soil=${Uri.encodeComponent(soilType)}&crop=${Uri.encodeComponent(cropType)}",
      );
      final res = await http.get(url).timeout(const Duration(seconds: 3));
      if (res.statusCode != 200) {
        throw Exception("ESP returned HTTP ${res.statusCode}");
      }
    } on TimeoutException {
      lastError = "Connection timed out while sending settings.";
    } catch (e) {
      lastError = "Failed to send settings. ${e.toString()}";
    } finally {
      isFetching = false;
      notifyListeners();
    }
  }

  /// Simple dry alert cooldown (avoid spamming user every refresh)
  void _maybeTriggerDryAlertCooldown() {
    final now = DateTime.now();
    if (_lastDryAlertAt == null || now.difference(_lastDryAlertAt!).inSeconds > 20) {
      _lastDryAlertAt = now;
      // This triggers UI dialog via listener pattern in Home screen.
      // Keep state minimal; Home reads isDry and shows dialog when it detects new dry state.
    }
  }
}

/// ---------------------------------------------------------------
/// Root App + Theme + Navigation Shell
/// ---------------------------------------------------------------
class SmartIrrigationApp extends StatefulWidget {
  const SmartIrrigationApp({super.key});

  @override
  State<SmartIrrigationApp> createState() => _SmartIrrigationAppState();
}

class _SmartIrrigationAppState extends State<SmartIrrigationApp> {
  final AppState state = AppState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1E88E5), // blue seed
      brightness: Brightness.light,
    ).copyWith(
      primary: const Color(0xFF1E88E5), // blue
      secondary: const Color(0xFF43A047), // green
      tertiary: const Color(0xFF00ACC1), // cyan-ish water
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Smart Irrigation",
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF6FAF8),
        cardTheme: CardTheme(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      home: AppStateScope(
        state: state,
        child: const Shell(),
      ),
    );
  }
}

/// Simple inherited notifier so we can access AppState anywhere without extra packages.
class AppStateScope extends InheritedNotifier<AppState> {
  final AppState state;

  const AppStateScope({
    super.key,
    required this.state,
    required Widget child,
  }) : super(notifier: state, child: child);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppStateScope>();
    assert(scope != null, "AppStateScope not found in widget tree");
    return scope!.state;
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      const HomeScreen(),
      const SettingsScreen(),
      const AdvisoryScreen(),
      const ChatbotScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text("Smart Irrigation"),
        centerTitle: true,
      ),
      body: screens[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_rounded), label: "Dashboard"),
          NavigationDestination(icon: Icon(Icons.tune_rounded), label: "Settings"),
          NavigationDestination(icon: Icon(Icons.lightbulb_rounded), label: "Advisory"),
          NavigationDestination(icon: Icon(Icons.chat_bubble_rounded), label: "Chatbot"),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------
/// A) Home/Dashboard Screen
/// ---------------------------------------------------------------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _timer;
  bool _dryDialogShownRecently = false;

  @override
  void initState() {
    super.initState();

    // Initial fetch
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final state = AppStateScope.of(context);
      await state.fetchMoistureAndMaybeAutoControl();
    });

    // Auto refresh every few seconds
    _timer = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (!mounted) return;
      final state = AppStateScope.of(context);
      await state.fetchMoistureAndMaybeAutoControl();

      // Dry alert dialog logic (simple)
      if (state.moisture != null && state.isDry && !_dryDialogShownRecently) {
        _dryDialogShownRecently = true;
        if (!mounted) return;
        _showDryAlertDialog(state);
        Future.delayed(const Duration(seconds: 20), () {
          _dryDialogShownRecently = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _showDryAlertDialog(AppState state) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Dry Soil Alert"),
        content: Text(
          "Moisture ${state.moisture} is above threshold ${state.finalThreshold}.\n\n"
          "Recommendation: irrigation needed.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await state.motorOnCommand();
            },
            child: const Text("Turn Motor ON"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);

    return RefreshIndicator(
      onRefresh: () => state.fetchMoistureAndMaybeAutoControl(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HeaderCard(state: state),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(child: _MoistureCard(state: state)),
              const SizedBox(width: 12),
              Expanded(child: _MotorCard(state: state)),
            ],
          ),

          const SizedBox(height: 12),
          _RecommendationCard(state: state),

          const SizedBox(height: 12),
          _ControlCard(state: state),

          if (state.lastError != null) ...[
            const SizedBox(height: 12),
            _ErrorBanner(message: state.lastError!),
          ],

          const SizedBox(height: 24),
          _FooterTips(),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final AppState state;
  const _HeaderCard({required this.state});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: Theme.of(context).colorScheme.secondary.withOpacity(0.12),
              child: Icon(Icons.eco_rounded, color: Theme.of(context).colorScheme.secondary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "IoT Smart Irrigation Dashboard",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Soil: ${state.soilType}   |   Crop: ${state.cropType}",
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: "Refresh",
              onPressed: state.isFetching ? null : () => state.fetchMoistureAndMaybeAutoControl(),
              icon: state.isFetching
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            )
          ],
        ),
      ),
    );
  }
}

class _MoistureCard extends StatelessWidget {
  final AppState state;
  const _MoistureCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.water_drop_rounded, color: scheme.tertiary),
                const SizedBox(width: 8),
                const Text(
                  "Soil Moisture",
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: LcdValue(
                valueText: state.moisture?.toString() ?? "---",
                labelText: "ADC Reading",
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _StatusPill(
                  text: state.moistureStatusText,
                  color: state.moisture == null
                      ? Colors.grey
                      : (state.isDry ? Colors.orange : Colors.green),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Threshold: ${state.finalThreshold}",
                    style: TextStyle(color: Colors.grey.shade700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MotorCard extends StatelessWidget {
  final AppState state;
  const _MotorCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.electrical_services_rounded, color: scheme.primary),
                const SizedBox(width: 8),
                const Text(
                  "Motor",
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Center(
              child: Icon(
                state.motorOn ? Icons.power_rounded : Icons.power_off_rounded,
                size: 52,
                color: state.motorOn ? scheme.secondary : Colors.grey,
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                state.motorOn ? "ON" : "OFF",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: state.motorOn ? scheme.secondary : Colors.grey.shade700,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _StatusPill(
                  text: state.autoMode ? "AUTO" : "MANUAL",
                  color: state.autoMode ? scheme.primary : Colors.grey,
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  final AppState state;
  const _RecommendationCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final bg = state.moisture == null
        ? Colors.grey.shade100
        : (state.isDry ? Colors.orange.shade50 : Colors.green.shade50);

    final iconColor = state.moisture == null
        ? Colors.grey
        : (state.isDry ? Colors.orange : Colors.green);

    return Card(
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withOpacity(0.05)),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: iconColor.withOpacity(0.12),
              child: Icon(Icons.recommend_rounded, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Recommendation",
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    state.recommendationText,
                    style: TextStyle(color: Colors.grey.shade800),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: scheme.primary.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }
}

class _ControlCard extends StatelessWidget {
  final AppState state;
  const _ControlCard({required this.state});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.settings_remote_rounded, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  "Controls",
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Auto mode
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Auto Motor Control (Threshold-based)"),
              subtitle: Text("If Dry → Motor ON, else OFF. Threshold = Soil + Crop adjustment."),
              value: state.autoMode,
              onChanged: (v) => state.setAutoMode(v),
            ),
            const SizedBox(height: 8),

            // Manual buttons
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: state.isFetching ? null : () => state.motorOnCommand(),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text("Motor ON"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: state.isFetching ? null : () => state.motorOffCommand(),
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text("Motor OFF"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FooterTips extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(
      "Tip: Use the Settings tab to set Soil and Crop for better irrigation intelligence.\n"
      "Make sure your phone is on the same WiFi network as the ESP8266.",
      style: TextStyle(color: Colors.grey.shade700),
      textAlign: TextAlign.center,
    );
  }
}

/// LCD-style widget for moisture value
class LcdValue extends StatelessWidget {
  final String valueText;
  final String labelText;

  const LcdValue({super.key, required this.valueText, required this.labelText});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B2B22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.tertiary.withOpacity(0.35)),
      ),
      child: Column(
        children: [
          Text(
            valueText,
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              color: Color(0xFF7CFFCB),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            labelText,
            style: TextStyle(
              fontSize: 12,
              color: const Color(0xFF7CFFCB).withOpacity(0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String text;
  final Color color;

  const _StatusPill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        text,
        style: TextStyle(fontWeight: FontWeight.w800, color: color),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.withOpacity(0.15)),
        ),
        child: Row(
          children: [
            Icon(Icons.wifi_off_rounded, color: Colors.red.shade700),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: Colors.red.shade800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------
/// B) Settings Screen
/// ---------------------------------------------------------------
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final soilOptions = const ["Sandy", "Loamy", "Clay"];
  final cropOptions = const ["Wheat", "Rice", "Vegetables", "Tomato"];

  late TextEditingController _espController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = AppStateScope.of(context);
      _espController = TextEditingController(text: state.espBaseUrl);
      setState(() {});
    });
  }

  @override
  void dispose() {
    _espController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.wifi_rounded, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    const Text(
                      "ESP8266 Connection",
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _espController,
                  decoration: const InputDecoration(
                    labelText: "ESP Base URL",
                    hintText: "http://192.168.4.1",
                    prefixIcon: Icon(Icons.link_rounded),
                  ),
                  onChanged: (v) => state.setEspBaseUrl(v),
                ),
                const SizedBox(height: 8),
                Text(
                  "Make sure your phone and ESP8266 are on the same WiFi network.",
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.grass_rounded, color: Theme.of(context).colorScheme.secondary),
                    const SizedBox(width: 8),
                    const Text(
                      "Soil & Crop Selection",
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                DropdownButtonFormField<String>(
                  value: state.soilType,
                  items: soilOptions
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) state.setSoil(v);
                  },
                  decoration: const InputDecoration(
                    labelText: "Soil Type",
                    prefixIcon: Icon(Icons.layers_rounded),
                  ),
                ),
                const SizedBox(height: 12),

                DropdownButtonFormField<String>(
                  value: state.cropType,
                  items: cropOptions
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) state.setCrop(v);
                  },
                  decoration: const InputDecoration(
                    labelText: "Crop Type",
                    prefixIcon: Icon(Icons.spa_rounded),
                  ),
                ),
                const SizedBox(height: 14),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: state.isFetching
                        ? null
                        : () async {
                            await state.sendSoilCropToEsp();
                            if (!mounted) return;
                            final msg = state.lastError == null
                                ? "Settings sent to ESP successfully."
                                : state.lastError!;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(msg)),
                            );
                          },
                    icon: const Icon(Icons.send_rounded),
                    label: const Text("Send to ESP8266"),
                  ),
                ),

                const SizedBox(height: 8),
                Text(
                  "ESP endpoint: /set?soil=TYPE&crop=TYPE",
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// ---------------------------------------------------------------
/// C) Advisory Screen
/// ---------------------------------------------------------------
class AdvisoryScreen extends StatelessWidget {
  const AdvisoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: scheme.secondary.withOpacity(0.12),
                  child: Icon(Icons.lightbulb_rounded, color: scheme.secondary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Crop-Soil Intelligence Advisory",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Based on Soil: ${state.soilType} and Crop: ${state.cropType}",
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.rule_rounded, color: scheme.primary),
                    const SizedBox(width: 8),
                    const Text("Irrigation Recommendations", style: TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 12),
                ...state.advisoryBullets.map(
                  (b) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check_circle_rounded, color: scheme.tertiary, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(b)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.insights_rounded, color: scheme.secondary),
                    const SizedBox(width: 8),
                    const Text("Quick Status", style: TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _InfoTile(
                        icon: Icons.layers_rounded,
                        title: "Soil Threshold",
                        value: "${state.soilBaseThreshold}",
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _InfoTile(
                        icon: Icons.spa_rounded,
                        title: "Crop Adjustment",
                        value: "${state.cropAdjustment}",
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _InfoTile(
                        icon: Icons.calculate_rounded,
                        title: "Final Threshold",
                        value: "${state.finalThreshold}",
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _InfoTile({required this.icon, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------
/// D) Chatbot Screen (OpenAI API)
/// ---------------------------------------------------------------
class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<ChatMessage> _messages = [];
  bool _sending = false;

  static const String systemPrompt =
      "You are an agriculture expert helping farmers with irrigation, crops, soil, fertilizers, and diseases. "
      "Provide simple and practical advice.";

  @override
  void initState() {
    super.initState();
    _messages.add(
      ChatMessage(
        role: ChatRole.assistant,
        text: "Hi! Ask me anything about irrigation, soil, crop care, fertilizers, or diseases.",
        time: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Theme.of(context).colorScheme.primary.withOpacity(0.06),
          child: Row(
            children: [
              const Icon(Icons.smart_toy_rounded),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Context: Soil=${state.soilType}, Crop=${state.cropType}, Moisture=${state.moisture ?? '---'}",
                  style: TextStyle(color: Colors.grey.shade800),
                ),
              ),
              IconButton(
                tooltip: "Clear chat",
                onPressed: _sending
                    ? null
                    : () {
                        setState(() {
                          _messages.clear();
                          _messages.add(
                            ChatMessage(
                              role: ChatRole.assistant,
                              text: "Chat cleared. How can I help you with your farm today?",
                              time: DateTime.now(),
                            ),
                          );
                        });
                      },
                icon: const Icon(Icons.delete_outline_rounded),
              )
            ],
          ),
        ),

        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length,
            itemBuilder: (context, i) {
              final m = _messages[i];
              return ChatBubble(message: m);
            },
          ),
        ),

        if (state.openAiApiKey.trim().isEmpty || state.openAiApiKey.contains("PASTE_YOUR"))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _WarningCard(
              text:
                  "OpenAI API key is not set. Paste it in AppState.openAiApiKey to enable chatbot responses.",
            ),
          ),

        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sending ? null : _send(state),
                    decoration: const InputDecoration(
                      hintText: "Type your question (irrigation, fertilizers, diseases...)",
                      prefixIcon: Icon(Icons.edit_rounded),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _sending ? null : () => _send(state),
                  child: _sending
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text("Send"),
                )
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _send(AppState state) async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _controller.clear();
      _messages.add(ChatMessage(role: ChatRole.user, text: text, time: DateTime.now()));
      _sending = true;
    });

    try {
      final reply = await OpenAiService(apiKey: state.openAiApiKey).askAgricultureAssistant(
        systemPrompt: systemPrompt,
        userQuestion: text,
        moisture: state.moisture,
        soil: state.soilType,
        crop: state.cropType,
        threshold: state.finalThreshold,
        isDry: state.moisture != null ? state.isDry : null,
      );

      setState(() {
        _messages.add(ChatMessage(role: ChatRole.assistant, text: reply, time: DateTime.now()));
      });
    } catch (e) {
      setState(() {
        _messages.add(
          ChatMessage(
            role: ChatRole.assistant,
            text: "I couldn't reach the AI service. ${e.toString()}",
            time: DateTime.now(),
          ),
        );
      });
    } finally {
      setState(() => _sending = false);
    }
  }
}

class _WarningCard extends StatelessWidget {
  final String text;
  const _WarningCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_rounded, color: Colors.orange.shade800),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(color: Colors.orange.shade900))),
          ],
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------
/// OpenAI Service (Chat Completions)
/// ---------------------------------------------------------------
class OpenAiService {
  final String apiKey;

  OpenAiService({required this.apiKey});

  Future<String> askAgricultureAssistant({
    required String systemPrompt,
    required String userQuestion,
    required int? moisture,
    required String soil,
    required String crop,
    required int threshold,
    required bool? isDry,
  }) async {
    if (apiKey.trim().isEmpty || apiKey.contains("PASTE_YOUR")) {
      throw Exception("OpenAI API key not configured.");
    }

    final context = """
Project: IoT-Based Smart Irrigation System with Crop-Soil Intelligence.
Current context:
- Soil type: $soil
- Crop type: $crop
- Moisture reading: ${moisture ?? 'N/A'}
- Threshold: $threshold
- Status: ${isDry == null ? 'Unknown' : (isDry ? 'Dry (needs irrigation)' : 'Wet (no irrigation)')}
User question: $userQuestion
""";

    final uri = Uri.parse("https://api.openai.com/v1/chat/completions");

    // Choose a widely available model; replace if your account uses a different one.
    // Examples: "gpt-4o-mini", "gpt-4.1-mini", etc.
    const model = "gpt-4o-mini";

    final body = {
      "model": model,
      "temperature": 0.4,
      "messages": [
        {"role": "system", "content": systemPrompt},
        {"role": "user", "content": context},
      ],
    };

    final res = await http
        .post(
          uri,
          headers: {
            "Authorization": "Bearer $apiKey",
            "Content-Type": "application/json",
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 12));

    if (res.statusCode != 200) {
      throw Exception("OpenAI error HTTP ${res.statusCode}: ${res.body}");
    }

    final decoded = jsonDecode(res.body);
    final content = decoded["choices"][0]["message"]["content"] as String?;
    return (content ?? "No response received.").trim();
  }
}

/// ---------------------------------------------------------------
/// Chat UI Widgets
/// ---------------------------------------------------------------
enum ChatRole { user, assistant }

class ChatMessage {
  final ChatRole role;
  final String text;
  final DateTime time;

  ChatMessage({required this.role, required this.text, required this.time});
}

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.role == ChatRole.user;

    final bg = isUser ? scheme.primary : Colors.white;
    final fg = isUser ? Colors.white : Colors.black87;
    final align = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black.withOpacity(isUser ? 0.0 : 0.06)),
            ),
            child: Text(message.text, style: TextStyle(color: fg, height: 1.35)),
          ),
          const SizedBox(height: 4),
          Text(
            _formatTime(message.time),
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return "$h:$m";
  }
}