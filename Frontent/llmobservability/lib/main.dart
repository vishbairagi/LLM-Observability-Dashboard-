// Flutter Dashboard (llm_dashboard/lib/main.dart)
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LLM Observability Dashboard',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const Dashboard(),
    );
  }
}

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  Map<String, dynamic> summary = {};
  List<dynamic> recent = [];
  final String baseUrl = "http://10.0.2.2:8000";  // Emulator: localhost -> 10.0.2.2; or your IP

  @override
  void initState() {
    super.initState();
    fetchData();
    Timer.periodic(const Duration(seconds: 5), (_) => fetchData());
  }

  Future<void> fetchData() async {
    try {
      final sumResp = await http.get(Uri.parse('$baseUrl/analytics/summary'));
      final recResp = await http.get(Uri.parse('$baseUrl/analytics/recent?limit=100'));

      setState(() {
        summary = json.decode(sumResp.body);
        recent = json.decode(recResp.body);
      });
    } catch (e) {
      // Handle error
    }
  }

  Future<void> exportCsv() async {
    List<List<dynamic>> csvData = [
      ['Timestamp', 'Input', 'Latency (s)', 'Total Tokens', 'Error', 'Feedback'],
      ...recent.map((call) => [
        call['timestamp'],
        call['input'],
        call['latency_sec'],
        call['total_tokens'],
        call['error'],
        call['feedback'],
      ])
    ];

    String csv = const ListToCsvConverter().convert(csvData);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/analytics.csv');
    await file.writeAsString(csv);

    await Share.shareXFiles([XFile(file.path)], text: 'LLM Analytics CSV');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LLM Observability Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: exportCsv,
          )
        ],
      ),
      body: summary.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        child: Column(
          children: [
            // Summary Cards
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _metricCard('Total Calls', summary['total_calls'] ?? 0),
                _metricCard('Avg Latency (s)', (summary['avg_latency'] ?? 0).toStringAsFixed(2)),
                _metricCard('Total Tokens', summary['total_tokens'] ?? 0),
                _metricCard('Errors', summary['errors'] ?? 0),
                _metricCard('👍', summary['positive_feedback'] ?? 0),
                _metricCard('👎', summary['negative_feedback'] ?? 0),
              ],
            ),

            // Alerts
            if ((summary['avg_latency'] ?? 0) > 5)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Card(
                  color: Colors.red,
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Alert: High Average Latency!', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ),

            // Token Usage Chart
            _chart('Token Usage Over Time', recent.reversed.toList(), (d) => d['total_tokens'] ?? 0),

            // Latency Chart
            _chart('Latency Over Time', recent.reversed.toList(), (d) => d['latency_sec'] ?? 0, color: Colors.orange),

            // Recent Calls List
            const Padding(padding: EdgeInsets.all(8), child: Text('Recent Calls', style: TextStyle(fontSize: 20))),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: recent.length > 20 ? 20 : recent.length,
              itemBuilder: (context, index) {
                var call = recent[index];
                return ListTile(
                  title: Text(call['input']?.substring(0, 50) ?? 'Error'),
                  subtitle: Text('Tokens: ${call['total_tokens']} | Latency: ${call['latency_sec']}s | Feedback: ${call['feedback'] ?? 'None'}'),
                );
              },
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: fetchData,
        child: const Icon(Icons.refresh),
      ),
    );
  }

  Widget _metricCard(String label, dynamic value) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [Text(label), Text(value.toString())],
        ),
      ),
    );
  }

  Widget _chart(String title, List dataSource, num Function(Map) yValueMapper, {Color? color}) {
    return SfCartesianChart(
      title: ChartTitle(text: title),
      primaryXAxis: const DateTimeAxis(dateFormat: DateFormat.Hm()),
      series: <LineSeries<Map<String, dynamic>, DateTime>>[
        LineSeries<Map<String, dynamic>, DateTime>(
          dataSource: dataSource,
          xValueMapper: (d, _) => DateTime.parse(d['timestamp']),
          yValueMapper: (d, _) => yValueMapper(d),
          color: color,
        )
      ],
    );
  }
}