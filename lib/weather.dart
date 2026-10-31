
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class Weather {
  Weather({required this.temperature, required this.code});

  final double temperature;
  final int code;

  factory Weather.fromJson(Map<String, dynamic> json) {
    return Weather(
      temperature: (json['temperature_2m'] as num).toDouble(),
      code: json['weather_code'] as int,
    );
  }
}

String describe(int code) {
  if (code == 0) return 'Clear sky';
  if (code <= 2) return 'Partly cloudy';
  if (code == 3) return 'Cloudy';
  if (code == 45 || code == 48) return 'Fog';
  if (code >= 51 && code <= 57) return 'Drizzle';
  if (code >= 61 && code <= 67) return 'Rain';
  if (code >= 80 && code <= 82) return 'Rain showers';
  if (code >= 95) return 'Thunderstorm';
  return 'Unknown';
}

Future<Weather> fetchWeather() async {
  final url = Uri.parse(
    'https://api.open-meteo.com/v1/forecast'
        '?latitude=-1.9441&longitude=30.0619'
        '&current=temperature_2m,weather_code',
  );

  final response = await http.get(url).timeout(
    const Duration(seconds: 5),
  );

  if (response.statusCode != 200) {
    throw Exception('Weather unavailable');
  }

  final data = jsonDecode(response.body) as Map<String, dynamic>;
  return Weather.fromJson(data['current'] as Map<String, dynamic>);
}

class WeatherBox extends StatefulWidget {
  const WeatherBox({super.key});

  @override
  State<WeatherBox> createState() => _WeatherBoxState();
}

class _WeatherBoxState extends State<WeatherBox> {
  Weather? weather;
  bool loading = true;
  bool error = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = false;
    });

    try {
      final w = await fetchWeather();
      if (!mounted) return;

      setState(() {
        weather = w;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        error = true;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;

    if (loading) {
      content = const CircularProgressIndicator();
    } else if (error) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Weather unavailable. Check your internet connection.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: load,
            child: const Text('Retry'),
          ),
        ],
      );
    } else {
      content = Text(
        'Kigali today: ${weather!.temperature.round()}°C, ${describe(weather!.code)}',
        style: const TextStyle(fontSize: 16),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: double.infinity,
          child: Center(child: content),
        ),
      ),
    );
  }
}
