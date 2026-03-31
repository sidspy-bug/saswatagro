import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const String kDefaultEspBaseUrl = 'http://192.168.4.1';
const String kOpenAiApiKey = 'PASTE_YOUR_OPENAI_API_KEY';

const Map<String, int> kSoilThresholds = {
  'Sandy': 500,
  'Loamy': 600,
  'Clay': 700,
};

const Map<String, int> kCropAdjustments = {
  'Rice': 50,
  'Wheat': -30,
  'Vegetables': 0,
  'Tomato': 0,
};

void main() {
  runApp(const SmartIrrigationApp());
}

class SmartIrrigationApp extends StatelessWidget {
  const SmartIrrigationApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF0F9D75),
        brightness: Brightness.light,
      ).copyWith(
        primary: const Color(0xFF0F9D75),
        secondary: const Color(0xFF1D6FD8),
        surface: const Color(0xFFF5FAF8),
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Irrigation System',
      theme: baseTheme.copyWith(
        scaffoldBackgroundColor: const Color(0xFFF2F8F7),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: false,
          backgroundColor: Colors.transparent,
          foregroundColor: Color(0xFF143A33),
        ),
        textTheme: baseTheme.textTheme.apply(
          bodyColor: const Color(0xFF18362F),
          displayColor: const Color(0xFF18362F),
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
  final List<ChatMessage> _messages = const [
    ChatMessage(
      text:
          'Hello. I am your irrigation assistant. Ask me about watering, crops, soil, fertilizers, or plant diseases.',
      isUser: false,
    ),
  ];

  int _currentIndex = 0;

  String _espBaseUrl = kDefaultEspBaseUrl;
  String _openAiApiKey = kOpenAiApiKey;

  String _selectedSoil = 'Loamy';
  String _selectedCrop = 'Wheat';

  int? _moisture;
  bool _motorOn = false;
  bool _autoControlEnabled = true;

  bool _isRefreshing = false;
  bool _isMotorBusy = false;
  bool _isSendingSettings = false;
  bool _isChatLoading = false;

  bool _dryAlertShown = false;

  String? _espError;
  DateTime? _lastUpdated;

  Timer? _refreshTimer;

  int get _threshold {
    final soilValue = kSoilThresholds[_selectedSoil] ?? 600;
    final cropValue = kCropAdjustments[_selectedCrop] ?? 0;
    return soilValue + cropValue;
  }

  bool get _isDry => _moisture != null && _moisture! > _threshold;

  String get _statusText {
    if (_moisture == null) return 'No data';
    return _isDry ? 'Dry' : 'Wet';
  }

  String get _recommendationText {
    if (_moisture == null) {
      return 'Connect to the ESP8266 to read live moisture data.';
    }

    if (_isDry) {
      return 'Soil is dry -> irrigation needed. Motor should stay ON until the moisture value drops below the threshold.';
    }

    return 'Soil is wet -> no irrigation required. Keep the motor OFF and avoid overwatering.';
  }

  @override
  void initState() {
    super.initState();
    _refreshMoistureData(showLoader: true);
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _refreshMoistureData();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Uri _buildEspUri(
    String path, {
    Map<String, String>? queryParameters,
  }) {
    final baseUri = Uri.parse(_espBaseUrl.trim());
    return baseUri.replace(
      path: path.startsWith('/') ? path : '/$path',
      queryParameters: queryParameters,
    );
  }

  Future<void> _refreshMoistureData({bool showLoader = false}) async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
    });

    try {
      final response = await http
          .get(_buildEspUri('/data'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final moistureValue = _parseMoistureValue(
        utf8.decode(response.bodyBytes),
      );

      if (!mounted) return;

      setState(() {
        _moisture = moistureValue;
        _espError = null;
        _lastUpdated = DateTime.now();
      });

      if (_isDry && !_dryAlertShown) {
        _dryAlertShown = true;
        _showSnackBar(
          'Alert: soil is dry. Irrigation is recommended.',
          background: const Color(0xFFD97706),
        );
      } else if (!_isDry) {
        _dryAlertShown = false;
      }

      if (_autoControlEnabled) {
        await _applyAutomaticControl();
      }
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _espError =
            'ESP8266 not connected. Check WiFi, IP address, and device power.';
      });

      if (showLoader) {
        _showSnackBar(
          'Could not connect to the ESP8266.',
          background: const Color(0xFFB91C1C),
        );
      }
    } finally {
      if (!mounted) return;

      setState(() {
        _isRefreshing = false;
      });
    }
  }

  int _parseMoistureValue(String body) {
    final trimmed = body.trim();

    final directValue = int.tryParse(trimmed);
    if (directValue != null) {
      return directValue;
    }

    final decoded = jsonDecode(trimmed);

    if (decoded is num) {
      return decoded.toInt();
    }

    if (decoded is Map) {
      final values = [
        decoded['moisture'],
        decoded['value'],
        decoded['sensor'],
        decoded['data'],
      ];

      for (final item in values) {
        if (item is num) {
          return item.toInt();
        }

        final parsed = int.tryParse(item == null ? '' : item.toString());
        if (parsed != null) {
          return parsed;
        }
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

    setState(() {
      _isMotorBusy = true;
    });

    try {
      final response = await http
          .get(_buildEspUri(turnOn ? '/on' : '/off'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      if (!mounted) return;

      setState(() {
        _motorOn = turnOn;
        _espError = null;
      });

      if (!silent) {
        _showSnackBar(
          turnOn ? 'Motor turned ON successfully.' : 'Motor turned OFF successfully.',
          background:
              turnOn ? const Color(0xFF0F9D75) : const Color(0xFF1D6FD8),
        );
      }
    } catch (_) {
      if (!mounted) return;

      final message = turnOn
          ? 'Unable to turn the motor ON. Make sure the ESP8266 is reachable.'
          : 'Unable to turn the motor OFF. Make sure the ESP8266 is reachable.';

      setState(() {
        _espError = message;
      });

      if (!silent) {
        _showSnackBar(
          message,
          background: const Color(0xFFB91C1C),
        );
      }
    } finally {
      if (!mounted) return;

      setState(() {
        _isMotorBusy = false;
      });
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
          .get(
            _buildEspUri(
              '/set',
              queryParameters: {
                'soil': soil,
                'crop': crop,
              },
            ),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      if (!mounted) return;

      setState(() {
        _espError = null;
      });

      _showSnackBar(
        'Soil and crop settings sent to the ESP8266.',
        background: const Color(0xFF0F9D75),
      );

      await _refreshMoistureData();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _espError = 'Failed to send soil and crop settings to the ESP8266.';
      });

      _showSnackBar(
        'Failed to send settings to the ESP8266.',
        background: const Color(0xFFB91C1C),
      );
    } finally {
      if (!mounted) return;

      setState(() {
        _isSendingSettings = false;
      });
    }
  }

  Future<void> _sendChatMessage(String question) async {
    final trimmedQuestion = question.trim();
    if (trimmedQuestion.isEmpty || _isChatLoading) return;

    setState(() {
      _messages.add(
        ChatMessage(
          text: trimmedQuestion,
          isUser: true,
        ),
      );
      _isChatLoading = true;
    });

    try {
      final key = _openAiApiKey.trim();

      if (key.isEmpty || key == 'PASTE_YOUR_OPENAI_API_KEY') {
        throw Exception('Set your OpenAI API key from the connection icon first.');
      }

      final prompt = '''
Farmer question:
$trimmedQuestion

Current field context:
- Moisture value: ${_moisture?.toString() ?? 'Unavailable'}
- Soil type: $_selectedSoil
- Crop type: $_selectedCrop
- Threshold: $_threshold
- Motor status: ${_motorOn ? 'ON' : 'OFF'}
- Soil status: $_statusText
- Recommendation: $_recommendationText

Please answer in simple, practical language with direct field advice.
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
                          'You are an agriculture expert helping farmers with irrigation, crops, soil, fertilizers, and diseases. Provide simple and practical advice.',
                    }
                  ],
                },
                {
                  'role': 'user',
                  'content': [
                    {
                      'type': 'input_text',
                      'text': prompt,
                    }
                  ],
                }
              ],
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception(_extractApiError(utf8.decode(response.bodyBytes)));
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final answer = _extractAssistantText(data);

      if (!mounted) return;

      setState(() {
        _messages.add(
          ChatMessage(
            text: answer,
            isUser: false,
          ),
        );
      });
    } catch (error) {
      if (!mounted) return;

      final cleanError = error.toString().replaceFirst('Exception: ', '');

      setState(() {
        _messages.add(
          ChatMessage(
            text: 'I could not reach the AI service. $cleanError',
            isUser: false,
            isError: true,
          ),
        );
      });
    } finally {
      if (!mounted) return;

      setState(() {
        _isChatLoading = false;
      });
    }
  }

  String _extractApiError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        final error = decoded['error'] as Map;
        final message = error['message'];
        if (message is String && message.isNotEmpty) {
          return message;
        }
      }
    } catch (_) {
      // Ignore JSON parse failures and fall back below.
    }

    return 'Request failed. Please verify the OpenAI API key and network connection.';
  }

  String _extractAssistantText(dynamic data) {
    if (data is Map) {
      final outputText = data['output_text'];
      if (outputText is String && outputText.trim().isNotEmpty) {
        return outputText.trim();
      }

      final output = data['output'];
      if (output is List) {
        for (final item in output) {
          if (item is Map) {
            final content = item['content'];
            if (content is List) {
              for (final part in content) {
                if (part is Map) {
                  final text = part['text'] ?? part['output_text'];
                  if (text is String && text.trim().isNotEmpty) {
                    return text.trim();
                  }
                }
              }
            }
          }
        }
      }

      final choices = data['choices'];
      if (choices is List && choices.isNotEmpty) {
        final firstChoice = choices.first;
        if (firstChoice is Map) {
          final message = firstChoice['message'];
          if (message is Map) {
            final content = message['content'];
            if (content is String && content.trim().isNotEmpty) {
              return content.trim();
            }
          }
        }
      }
    }

    throw const FormatException('No AI text response found');
  }

  void _showSnackBar(
    String message, {
    Color background = const Color(0xFF143A33),
  }) {
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
      backgroundColor: const Color(0xFFF7FBFA),
      builder: (sheetContext) {
        return ConnectionSheet(
          initialEspBaseUrl: _espBaseUrl,
          initialOpenAiApiKey:
              _openAiApiKey == kOpenAiApiKey ? '' : _openAiApiKey,
          onSave: (espBaseUrl, openAiApiKey) {
            setState(() {
              _espBaseUrl = espBaseUrl.trim();
              _openAiApiKey = openAiApiKey.trim();
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
    const pageTitles = [
      'Dashboard',
      'Settings',
      'Advisory',
      'AI Chatbot',
    ];

    final pages = [
      DashboardScreen(
        moisture: _moisture,
        threshold: _threshold,
        motorOn: _motorOn,
        selectedSoil: _selectedSoil,
        selectedCrop: _selectedCrop,
        statusText: _statusText,
        isDry: _isDry,
        recommendation: _recommendationText,
        errorMessage: _espError,
        lastUpdated: _lastUpdated,
        isRefreshing: _isRefreshing,
        isMotorBusy: _isMotorBusy,
        autoControlEnabled: _autoControlEnabled,
        onRefresh: () => _refreshMoistureData(showLoader: true),
        onMotorToggle: _setMotor,
        onAutoControlChanged: (value) {
          setState(() {
            _autoControlEnabled = value;
          });

          if (value) {
            _applyAutomaticControl();
          }
        },
      ),
      SettingsScreen(
        selectedSoil: _selectedSoil,
        selectedCrop: _selectedCrop,
        threshold: _threshold,
        isSending: _isSendingSettings,
        espBaseUrl: _espBaseUrl,
        onApply: _applySettings,
      ),
      AdvisoryScreen(
        selectedSoil: _selectedSoil,
        selectedCrop: _selectedCrop,
        moisture: _moisture,
        threshold: _threshold,
        isDry: _isDry,
        recommendation: _recommendationText,
      ),
      ChatbotScreen(
        messages: _messages,
        isLoading: _isChatLoading,
        selectedSoil: _selectedSoil,
        selectedCrop: _selectedCrop,
        moisture: _moisture,
        onSend: _sendChatMessage,
      ),
    ];

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        titleSpacing: 18,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'IoT-Based Smart Irrigation System',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
            Text(
              pageTitles[_currentIndex],
              style: TextStyle(
                color: Colors.black.withOpacity(0.55),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _isRefreshing
                ? null
                : () => _refreshMoistureData(showLoader: true),
            tooltip: 'Refresh sensor data',
            icon: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            onPressed: _openConnectionSheet,
            tooltip: 'ESP and API setup',
            icon: const Icon(Icons.router_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFFE8F7F2),
              Color(0xFFF6FCFF),
              Color(0xFFEFF4FF),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          top: false,
          child: IndexedStack(
            index: _currentIndex,
            children: pages,
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        height: 74,
        selectedIndex: _currentIndex,
        indicatorColor: const Color(0xFFCFEEE0),
        backgroundColor: Colors.white.withOpacity(0.95),
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_customize_outlined),
            selectedIcon: Icon(Icons.dashboard_customize),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Settings',
          ),
          NavigationDestination(
            icon: Icon(Icons.eco_outlined),
            selectedIcon: Icon(Icons.eco),
            label: 'Advisory',
          ),
          NavigationDestination(
            icon: Icon(Icons.smart_toy_outlined),
            selectedIcon: Icon(Icons.smart_toy),
            label: 'Chatbot',
          ),
        ],
      ),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.moisture,
    required this.threshold,
    required this.motorOn,
    required this.selectedSoil,
    required this.selectedCrop,
    required this.statusText,
    required this.isDry,
    required this.recommendation,
    required this.errorMessage,
    required this.lastUpdated,
    required this.isRefreshing,
    required this.isMotorBusy,
    required this.autoControlEnabled,
    required this.onRefresh,
    required this.onMotorToggle,
    required this.onAutoControlChanged,
  });

  final int? moisture;
  final int threshold;
  final bool motorOn;
  final String selectedSoil;
  final String selectedCrop;
  final String statusText;
  final bool isDry;
  final String recommendation;
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          final cardWidth = wide
              ? (constraints.maxWidth - 16) / 2
              : constraints.maxWidth;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FrostedCard(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF0E9F6E),
                    Color(0xFF1778D4),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.water_drop_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Live Field Dashboard',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 22,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            statusText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.82),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.12),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SOIL MOISTURE',
                            style: TextStyle(
                              color: Colors.greenAccent.shade100,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2.2,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                moisture?.toString() ?? '---',
                                style: const TextStyle(
                                  color: Colors.greenAccent,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 42,
                                  letterSpacing: 4,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'ADC',
                                style: TextStyle(
                                  color: Colors.greenAccent.shade100,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Threshold: $threshold | Last update: ${formatTime(lastUpdated)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton.filledTonal(
                          onPressed: isRefreshing ? null : onRefresh,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white.withOpacity(0.18),
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: 16),
                StatusBanner(
                  color: const Color(0xFFFEF2F2),
                  borderColor: const Color(0xFFFCA5A5),
                  icon: Icons.wifi_off_rounded,
                  title: 'Connection warning',
                  message: errorMessage!,
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: cardWidth,
                    child: MetricCard(
                      title: 'Motor Status',
                      value: motorOn ? 'ON' : 'OFF',
                      subtitle:
                          motorOn ? 'Pump is supplying water' : 'Pump is idle',
                      icon: Icons.power_settings_new_rounded,
                      accent: motorOn
                          ? const Color(0xFF0F9D75)
                          : const Color(0xFF64748B),
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: MetricCard(
                      title: 'Soil Type',
                      value: selectedSoil,
                      subtitle: 'Soil base threshold: ${kSoilThresholds[selectedSoil] ?? 0}',
                      icon: Icons.landscape_rounded,
                      accent: const Color(0xFF14B8A6),
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: MetricCard(
                      title: 'Crop Type',
                      value: selectedCrop,
                      subtitle: 'Crop adjustment: ${kCropAdjustments[selectedCrop] ?? 0}',
                      icon: Icons.grass_rounded,
                      accent: const Color(0xFF22C55E),
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: MetricCard(
                      title: 'Field Status',
                      value: statusText,
                      subtitle: moisture == null
                          ? 'Waiting for sensor data'
                          : isDry
                              ? 'Soil is dry, irrigation needed'
                              : 'Soil is wet, irrigation not required',
                      icon: Icons.opacity_rounded,
                      accent: isDry
                          ? const Color(0xFFD97706)
                          : const Color(0xFF2563EB),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FrostedCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Recommendation',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDry
                            ? const Color(0xFFFFF7ED)
                            : const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isDry
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFF60A5FA),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            isDry
                                ? Icons.warning_amber_rounded
                                : Icons.verified_rounded,
                            color: isDry
                                ? const Color(0xFFD97706)
                                : const Color(0xFF2563EB),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              recommendation,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: autoControlEnabled,
                      onChanged: onAutoControlChanged,
                      title: const Text(
                        'Auto motor control',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: const Text(
                        'Automatically switch the motor based on the moisture threshold.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: isMotorBusy ? null : () => onMotorToggle(true),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: const Color(0xFF0F9D75),
                            ),
                            icon: isMotorBusy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.play_arrow_rounded),
                            label: const Text('Motor ON'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: isMotorBusy ? null : () => onMotorToggle(false),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            icon: const Icon(Icons.stop_rounded),
                            label: const Text('Motor OFF'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.selectedSoil,
    required this.selectedCrop,
    required this.threshold,
    required this.isSending,
    required this.espBaseUrl,
    required this.onApply,
  });

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

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FrostedCard(
            gradient: const LinearGradient(
              colors: [
                Color(0xFFDBF4E8),
                Color(0xFFEAF4FF),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Crop and Soil Intelligence',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Send soil and crop details to your ESP8266 using the /set endpoint.\nDevice: ${widget.espBaseUrl}',
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.65),
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FrostedCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select Soil Type',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _soil,
                  decoration: _dropdownDecoration('Choose soil type'),
                  items: kSoilThresholds.keys
                      .map(
                        (soil) => DropdownMenuItem<String>(
                          value: soil,
                          child: Text(soil),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _soil = value;
                    });
                  },
                ),
                const SizedBox(height: 20),
                const Text(
                  'Select Crop Type',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _crop,
                  decoration: _dropdownDecoration('Choose crop type'),
                  items: const [
                    'Wheat',
                    'Rice',
                    'Vegetables',
                    'Tomato',
                  ]
                      .map(
                        (crop) => DropdownMenuItem<String>(
                          value: crop,
                          child: Text(crop),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _crop = value;
                    });
                  },
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7FAFC),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFFD9E6F2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Threshold Preview',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Soil base: ${kSoilThresholds[_soil] ?? 0}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Crop adjustment: ${kCropAdjustments[_crop] ?? 0}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Final threshold: $previewThreshold',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F9D75),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: widget.isSending
                        ? null
                        : () async {
                            await widget.onApply(_soil, _crop);
                          },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: const Color(0xFF0F9D75),
                    ),
                    icon: widget.isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
                    label: const Text('Send to ESP8266'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _dropdownDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF8FBFA),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFD8E6E1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFD8E6E1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFF0F9D75), width: 1.5),
      ),
    );
  }
}

class AdvisoryScreen extends StatelessWidget {
  const AdvisoryScreen({
    super.key,
    required this.selectedSoil,
    required this.selectedCrop,
    required this.moisture,
    required this.threshold,
    required this.isDry,
    required this.recommendation,
  });

  final String selectedSoil;
  final String selectedCrop;
  final int? moisture;
  final int threshold;
  final bool isDry;
  final String recommendation;

  @override
  Widget build(BuildContext context) {
    final adviceItems = buildAdvisoryItems(
      soil: selectedSoil,
      crop: selectedCrop,
      moisture: moisture,
      threshold: threshold,
      isDry: isDry,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FrostedCard(
            gradient: const LinearGradient(
              colors: [
                Color(0xFFE7F8EE),
                Color(0xFFEFF6FF),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Smart Advisory',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Advisory is generated using the selected soil type, crop profile, and moisture threshold.',
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.65),
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FrostedCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isDry ? Icons.water_drop_rounded : Icons.check_circle_rounded,
                  color: isDry
                      ? const Color(0xFFD97706)
                      : const Color(0xFF0F9D75),
                  size: 32,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isDry ? 'Irrigation needed' : 'Irrigation not needed',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        recommendation,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ...adviceItems.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: AdviceCard(item: item),
            ),
          ),
        ],
      ),
    );
  }
}

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({
    super.key,
    required this.messages,
    required this.isLoading,
    required this.selectedSoil,
    required this.selectedCrop,
    required this.moisture,
    required this.onSend,
  });

  final List<ChatMessage> messages;
  final bool isLoading;
  final String selectedSoil;
  final String selectedCrop;
  final int? moisture;
  final Future<void> Function(String question) onSend;

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
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FrostedCard(
            gradient: const LinearGradient(
              colors: [
                Color(0xFFE5F4FF),
                Color(0xFFEAF8F1),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI Farmer Assistant',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ContextChip(
                      icon: Icons.landscape_rounded,
                      label: widget.selectedSoil,
                    ),
                    ContextChip(
                      icon: Icons.grass_rounded,
                      label: widget.selectedCrop,
                    ),
                    ContextChip(
                      icon: Icons.opacity_rounded,
                      label: widget.moisture?.toString() ?? 'No moisture data',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: FrostedCard(
              padding: const EdgeInsets.all(12),
              child: ListView.separated(
                controller: _scrollController,
                itemCount: widget.messages.length + (widget.isLoading ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  if (index >= widget.messages.length) {
                    return const ChatBubble(
                      text: 'Thinking...',
                      isUser: false,
                      isLoading: true,
                    );
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
          const SizedBox(height: 16),
          FrostedCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _handleSend(),
                    decoration: InputDecoration(
                      hintText: 'Ask about irrigation, disease, or fertilizers...',
                      filled: true,
                      fillColor: const Color(0xFFF7FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(
                          color: Color(0xFFD8E6E1),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(
                          color: Color(0xFFD8E6E1),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(
                          color: Color(0xFF1D6FD8),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: widget.isLoading ? null : _handleSend,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    backgroundColor: const Color(0xFF1D6FD8),
                  ),
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Send'),
                ),
              ],
            ),
          ),
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
    required this.onSave,
  });

  final String initialEspBaseUrl;
  final String initialOpenAiApiKey;
  final void Function(String espBaseUrl, String openAiApiKey) onSave;

  @override
  State<ConnectionSheet> createState() => _ConnectionSheetState();
}

class _ConnectionSheetState extends State<ConnectionSheet> {
  late final TextEditingController _espController;
  late final TextEditingController _apiKeyController;

  @override
  void initState() {
    super.initState();
    _espController = TextEditingController(text: widget.initialEspBaseUrl);
    _apiKeyController = TextEditingController(text: widget.initialOpenAiApiKey);
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
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottomInset + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Connection Setup',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter the ESP8266 base URL and your OpenAI API key. For production, move the API key to a secure backend service.',
            style: TextStyle(
              color: Colors.black.withOpacity(0.65),
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _espController,
            decoration: _inputDecoration(
              label: 'ESP8266 Base URL',
              hint: 'http://192.168.4.1',
              icon: Icons.router_rounded,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _apiKeyController,
            obscureText: true,
            decoration: _inputDecoration(
              label: 'OpenAI API Key',
              hint: 'sk-...',
              icon: Icons.key_rounded,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                widget.onSave(
                  _espController.text,
                  _apiKeyController.text,
                );
              },
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: const Color(0xFF0F9D75),
              ),
              icon: const Icon(Icons.save_rounded),
              label: const Text('Save Connection Settings'),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: const Color(0xFFF8FBFA),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFD8E6E1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFD8E6E1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFF0F9D75), width: 1.5),
      ),
    );
  }
}

class FrostedCard extends StatelessWidget {
  const FrostedCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.gradient,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        gradient: gradient,
        color: gradient == null ? Colors.white.withOpacity(0.92) : null,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.45),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return FrostedCard(
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.6),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.55),
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AdviceCard extends StatelessWidget {
  const AdviceCard({
    super.key,
    required this.item,
  });

  final AdviceItem item;

  @override
  Widget build(BuildContext context) {
    return FrostedCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: item.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(item.icon, color: item.color),
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
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.description,
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.68),
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.color,
    required this.borderColor,
    required this.icon,
    required this.title,
    required this.message,
  });

  final Color color;
  final Color borderColor;
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFB91C1C)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF7F1D1D),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF7F1D1D),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ContextChip extends StatelessWidget {
  const ContextChip({
    super.key,
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD9E6F2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF1D6FD8)),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
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
    final bubbleColor = isUser
        ? const Color(0xFF1D6FD8)
        : isError
            ? const Color(0xFFFEF2F2)
            : const Color(0xFFF4F8F7);

    final textColor = isUser
        ? Colors.white
        : isError
            ? const Color(0xFF991B1B)
            : const Color(0xFF18362F);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isUser
                  ? Colors.transparent
                  : isError
                      ? const Color(0xFFFCA5A5)
                      : const Color(0xFFD8E6E1),
            ),
          ),
          child: isLoading
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      text,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                )
              : Text(
                  text,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
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
  required String crop,
  required int? moisture,
  required int threshold,
  required bool isDry,
}) {
  final soilAdvice = {
    'Sandy':
        'Sandy soil drains quickly. Use short and frequent irrigation cycles, add mulch, and check moisture often during hot weather.',
    'Loamy':
        'Loamy soil holds a balanced amount of water. Deep watering with steady intervals usually gives the best root development.',
    'Clay':
        'Clay soil stores water for longer. Irrigate slowly and avoid standing water because roots can suffer from poor aeration.',
  };

  final cropAdvice = {
    'Wheat':
        'Wheat needs controlled moisture. Avoid waterlogging during early growth and reduce excess irrigation near maturity.',
    'Rice':
        'Rice performs better with higher moisture availability. Maintain stable water conditions and watch for prolonged dryness.',
    'Vegetables':
        'Vegetables need consistent moisture. Morning irrigation is ideal and helps reduce heat stress and leaf diseases.',
    'Tomato':
        'Tomato plants prefer even watering. Sudden overwatering can lead to fruit cracking and weak root health.',
  };

  final moistureSummary = moisture == null
      ? 'Live moisture data is unavailable. Use the dashboard refresh action after the ESP8266 is connected.'
      : 'Current moisture is $moisture with a decision threshold of $threshold. ${isDry ? 'The field is drier than recommended.' : 'The root zone is currently in the safe moisture range.'}';

  return [
    AdviceItem(
      title: 'Irrigation Recommendation',
      description: isDry
          ? 'Water is required now. Run the motor, inspect emitter flow, and monitor the field until the reading drops under the threshold.'
          : 'Avoid overwatering. Keep the motor OFF, monitor runoff, and recheck moisture before the next irrigation cycle.',
      icon: Icons.water_rounded,
      color: isDry ? const Color(0xFFD97706) : const Color(0xFF2563EB),
    ),
    AdviceItem(
      title: '$soil Soil Guidance',
      description: soilAdvice[soil] ?? soilAdvice['Loamy']!,
      icon: Icons.landscape_rounded,
      color: const Color(0xFF14B8A6),
    ),
    AdviceItem(
      title: '$crop Crop Guidance',
      description: cropAdvice[crop] ?? cropAdvice['Vegetables']!,
      icon: Icons.grass_rounded,
      color: const Color(0xFF22C55E),
    ),
    AdviceItem(
      title: 'Sensor Insight',
      description: moistureSummary,
      icon: Icons.analytics_rounded,
      color: const Color(0xFF1D6FD8),
    ),
    AdviceItem(
      title: 'Practical Field Action',
      description:
          'Inspect the pump line, verify nozzle flow, and look for signs of leaf curling, yellowing, or fungal growth before adjusting irrigation duration.',
      icon: Icons.build_circle_rounded,
      color: const Color(0xFF8B5CF6),
    ),
  ];
}

String formatTime(DateTime? dateTime) {
  if (dateTime == null) return 'Not synced yet';

  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final second = dateTime.second.toString().padLeft(2, '0');

  return '$hour:$minute:$second';
}

