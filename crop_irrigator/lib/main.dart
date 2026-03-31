// SASWAT AGRO - PRODUCTION LEVEL UI (UPGRADED)
// Clean, modern, farmer-friendly + multi-feature dashboard

import 'package:flutter/material.dart';

void main() {
  runApp(const SaswatAgroApp());
}

class SaswatAgroApp extends StatelessWidget {
  const SaswatAgroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Saswat Agro',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  Widget buildCard(String title, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [color.withOpacity(0.8), color],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          )
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 40, color: Colors.white),
          const SizedBox(height: 10),
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold))
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Saswat Agro 🌱"),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Smart Farming Dashboard",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),

            // STATUS CARD
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: Colors.green.shade50,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Soil Status",
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 5),
                      Text("Dry ❌ Water Needed",
                          style: TextStyle(fontSize: 16))
                    ],
                  ),
                  Icon(Icons.water_drop, color: Colors.blue, size: 40)
                ],
              ),
            ),

            const SizedBox(height: 20),

            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 15,
                mainAxisSpacing: 15,
                children: [
                  buildCard("Crops", Icons.agriculture, Colors.green),
                  buildCard("Weather", Icons.cloud, Colors.blue),
                  buildCard("AI Assistant", Icons.smart_toy, Colors.orange),
                  buildCard("Irrigation", Icons.water, Colors.teal),
                  buildCard("Farming Types", Icons.eco, Colors.brown),
                  buildCard("Settings", Icons.settings, Colors.grey),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
