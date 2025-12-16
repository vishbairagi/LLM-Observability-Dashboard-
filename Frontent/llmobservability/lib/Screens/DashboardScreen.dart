import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic> summary = {};
  List<dynamic> recentCalls = [];
  bool isLoading = true;
  String errorMessage = '';

  final String baseUrl = "http://10.0.2.2:8000"; // Emulator
  // final String baseUrl = "http://YOUR_PC_IP:8000"; // Real device

  late Timer timer;

  @override
  void initState() {
    super.initState();
    fetchData();
    timer = Timer.periodic(const Duration(seconds: 5), (_) => fetchData());
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  Future<void> fetchData() async {
    try {
      final sumResponse = await http.get(Uri.parse('$baseUrl/analytics/summary'));
      final recentResponse = await http.get(Uri.parse('$baseUrl/analytics/recent?limit=200'));

      if (sumResponse.statusCode == 200 && recentResponse.statusCode == 200) {
        setState(() {
          summary = json.decode(sumResponse.body);
          recentCalls = json.decode(recentResponse.body);
          isLoading = false;
          errorMessage = '';
        });
      } else {
        throw Exception("API error: ${sumResponse.statusCode}");
      }
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = 'Connection error: $e';
      });
    }
  }

  Future<void> exportToCsv() async {
    if (recentCalls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No data to export')),
      );
      return;
    }

    List<List<dynamic>> rows = [];
    rows.add([
      "Timestamp",
      "Input",
      "Latency (s)",
      "Total Tokens",
      "Error",
      "Feedback"
    ]);

    for (var call in recentCalls) {
      rows.add([
        DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.parse(call['timestamp'])),
        call['input'] ?? '',
        call['latency_sec'] ?? 0,
        call['total_tokens'] ?? 0,
        call['error'] ?? '',
        call['feedback'] == 1 ? 'Good' : call['feedback'] == -1 ? 'Bad' : 'None',
      ]);
    }

    String csv = const ListToCsvConverter().convert(rows);

    final directory = await getTemporaryDirectory();
    final path = '${directory.path}/llm_analytics_${DateTime.now().millisecondsSinceEpoch}.csv';
    final file = File(path);
    await file.writeAsString(csv);

    await Share.shareXFiles([XFile(path)], text: 'LLM Observability Analytics');
  }

  void showCallDetails(Map<String, dynamic> call) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Call Details'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _detailRow('Timestamp', DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.parse(call['timestamp']))),
                const Divider(),
                _detailRow('Input (Question)', call['input'] ?? 'None'),
                const Divider(),
                _detailRow('Output (Response)', call['output'] ?? 'None'),
                const Divider(),
                _detailRow('Latency', '${call['latency_sec'] ?? 'N/A'} seconds'),
                _detailRow('Prompt Tokens', '${call['prompt_tokens'] ?? 'N/A'}'),
                _detailRow('Completion Tokens', '${call['completion_tokens'] ?? 'N/A'}'),
                _detailRow('Total Tokens', '${call['total_tokens'] ?? 'N/A'}'),
                _detailRow('Feedback',
                    call['feedback'] == 1 ? 'Good 👍' :
                    call['feedback'] == -1 ? 'Bad 👎' : 'None'),
                if (call['error'] != null)
                  _detailRow('Error', call['error'], color: Colors.red),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, dynamic value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black87, fontSize: 15),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: value.toString(), style: TextStyle(color: color)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final avgLatency = (summary['avg_latency'] ?? 0).toDouble();

    return Scaffold(
      appBar: AppBar(
        title: const Text('LLM Observability Dashboard'),
        actions: [
          IconButton(icon: const Icon(Icons.download), onPressed: exportToCsv, tooltip: 'Export CSV'),
          IconButton(icon: const Icon(Icons.refresh), onPressed: fetchData, tooltip: 'Refresh'),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage.isNotEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, color: Colors.red, size: 60),
            Text(errorMessage, style: const TextStyle(color: Colors.red)),
            ElevatedButton(onPressed: fetchData, child: const Text('Retry')),
          ],
        ),
      )
          : RefreshIndicator(
        onRefresh: fetchData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Alerts
              if (avgLatency > 5)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red)),
                  child: const Text('⚠️ High Average Latency Detected!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
                ),
              if ((summary['errors'] ?? 0) > 0)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(12)),
                  child: Text('⚠️ ${summary['errors']} Error(s) Recorded', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange)),
                ),

              // Summary Cards

              const SizedBox(height: 24),

              // Charts
              _buildChart(title: 'Token Usage Over Time', yMapper: (data) => (data['total_tokens'] ?? 0).toDouble(), color: Colors.blue),
              const SizedBox(height: 24),
              _buildChart(title: 'Latency Over Time', yMapper: (data) => (data['latency_sec'] ?? 0).toDouble(), color: Colors.orange),

              const SizedBox(height: 24),

              // Recent Calls with Tap to View Details
              const Text('Recent Calls', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: recentCalls.length > 20 ? 20 : recentCalls.length,
                itemBuilder: (context, index) {
                  final call = recentCalls[recentCalls.length - 1 - index];
                  final feedback = call['feedback'];

                  return Card(
                    child: ListTile(
                      onTap: () => showCallDetails(call),
                      title: Text(
                        (call['input'] ?? 'No input').toString().length > 60
                            ? '${(call['input'] ?? '').toString().substring(0, 60)}...'
                            : call['input'] ?? 'No input',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        'Latency: ${call['latency_sec']}s | Tokens: ${call['total_tokens']} | '
                            'Feedback: ${feedback == 1 ? 'Good' : feedback == -1 ? 'Bad' : 'None'}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (call['error'] != null) const Icon(Icons.error, color: Colors.red),
                          const Icon(Icons.arrow_forward_ios, size: 16),
                        ],
                      ),
                      isThreeLine: true,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard(String title, dynamic value, IconData icon, {Color? color}) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: color ?? Colors.deepPurple),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontSize: 13, color: Colors.grey), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value.toString(),
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color ?? Colors.black),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart({
    required String title,
    required double Function(Map<String, dynamic>) yMapper,
    required Color color,
  }) {
    if (recentCalls.isEmpty) {
      return const Card(child: Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No data yet'))));
    }

    final List<Map<String, dynamic>> chartData =
    recentCalls.reversed.map((e) => e as Map<String, dynamic>).toList();

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child: SfCartesianChart(
                primaryXAxis: DateTimeAxis(dateFormat: DateFormat.Hm(), title: AxisTitle(text: 'Time')),
                primaryYAxis: NumericAxis(title: AxisTitle(text: title.contains('Token') ? 'Tokens' : 'Seconds')),
                series: <LineSeries<Map<String, dynamic>, DateTime>>[
                  LineSeries<Map<String, dynamic>, DateTime>(
                    dataSource: chartData,
                    xValueMapper: (data, _) => DateTime.parse(data['timestamp']),
                    yValueMapper: (data, _) => yMapper(data),
                    color: color,
                    width: 3,
                    markerSettings: const MarkerSettings(isVisible: true),
                  ),
                ],
                tooltipBehavior: TooltipBehavior(enable: true),
                zoomPanBehavior: ZoomPanBehavior(enablePanning: true, enablePinching: true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}