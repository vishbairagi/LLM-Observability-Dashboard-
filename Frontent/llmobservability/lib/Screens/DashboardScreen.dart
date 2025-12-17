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
  bool liveUpdatesEnabled = true;

  final String baseUrl = "http://10.0.2.2:8000";

  late Timer timer;

  // Professional color scheme
  static const primaryColor = Color(0xFF6366F1); // Indigo
  static const successColor = Color(0xFF10B981); // Green
  static const warningColor = Color(0xFFF59E0B); // Amber
  static const errorColor = Color(0xFFEF4444); // Red
  static const backgroundColor = Color(0xFFF9FAFB);
  static const cardColor = Colors.white;
  static const textPrimary = Color(0xFF111827);
  static const textSecondary = Color(0xFF6B7280);

  @override
  void initState() {
    super.initState();
    fetchData();
    startTimer();
  }

  void startTimer() {
    timer = Timer.periodic(const Duration(seconds: 10), (_) => fetchData());
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  Future<void> fetchData() async {
    if (!mounted) return;
    if (recentCalls.isEmpty) {
      setState(() => isLoading = true);
    }
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
        SnackBar(
          content: const Text('No data to export'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: warningColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      return;
    }

    List<List<dynamic>> rows = [];
    rows.add(["Timestamp", "Input", "Latency (s)", "Total Tokens", "Error", "Feedback"]);

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

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Data exported successfully'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: successColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  void showCallDetails(Map<String, dynamic> call) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: primaryColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.info_outline, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Call Details',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: textPrimary,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                      color: textSecondary,
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _detailSection('Time Information', [
                        _detailRow('Timestamp', DateFormat('MMM dd, yyyy • HH:mm:ss').format(DateTime.parse(call['timestamp']))),
                      ]),
                      const SizedBox(height: 16),
                      _detailSection('Request & Response', [
                        _detailRow('Input', call['input'] ?? 'None', multiline: true),
                        _detailRow('Output', call['output'] ?? 'None', multiline: true),
                      ]),
                      const SizedBox(height: 16),
                      _detailSection('Performance Metrics', [
                        _detailRow('Latency', '${call['latency_sec'] ?? 'N/A'} seconds',
                            color: (call['latency_sec'] ?? 0) > 5 ? errorColor : successColor),
                        _detailRow('Prompt Tokens', '${call['prompt_tokens'] ?? 'N/A'}'),
                        _detailRow('Completion Tokens', '${call['completion_tokens'] ?? 'N/A'}'),
                        _detailRow('Total Tokens', '${call['total_tokens'] ?? 'N/A'}',
                            color: primaryColor),
                      ]),
                      const SizedBox(height: 16),
                      _detailSection('Feedback & Status', [
                        _detailRow('Feedback',
                            call['feedback'] == 1 ? '👍 Positive' :
                            call['feedback'] == -1 ? '👎 Negative' : '— No feedback',
                            color: call['feedback'] == 1 ? successColor :
                            call['feedback'] == -1 ? errorColor : textSecondary),
                        if (call['error'] != null)
                          _detailRow('Error', call['error'], color: errorColor, multiline: true),
                      ]),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: textSecondary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _detailRow(String label, dynamic value, {Color? color, bool multiline = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.toString(),
            style: TextStyle(
              fontSize: 15,
              color: color ?? textPrimary,
              height: multiline ? 1.5 : 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String title, dynamic value, IconData icon, {Color? color}) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (color ?? primaryColor).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 20, color: color ?? primaryColor),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              color: textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.toString(),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color ?? textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart({
    required String title,
    required double Function(Map<String, dynamic>) yMapper,
    required Color color,
  }) {
    if (recentCalls.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        padding: const EdgeInsets.all(32),
        child: const Center(
          child: Column(
            children: [
              Icon(Icons.show_chart, size: 48, color: textSecondary),
              SizedBox(height: 8),
              Text('No data available', style: TextStyle(color: textSecondary)),
            ],
          ),
        ),
      );
    }

    final chartData = recentCalls.reversed.map((e) => e as Map<String, dynamic>).toList();

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.show_chart, size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 280,
            child: SfCartesianChart(
              plotAreaBorderWidth: 0,
              primaryXAxis: DateTimeAxis(
                dateFormat: DateFormat.Hm(),
                majorGridLines: const MajorGridLines(width: 0),
                axisLine: const AxisLine(width: 0),
                labelStyle: const TextStyle(color: textSecondary, fontSize: 11),
              ),
              primaryYAxis: NumericAxis(
                majorGridLines: MajorGridLines(width: 1, color: Colors.grey.shade200),
                axisLine: const AxisLine(width: 0),
                labelStyle: const TextStyle(color: textSecondary, fontSize: 11),
              ),
              series: <LineSeries<Map<String, dynamic>, DateTime>>[
                LineSeries<Map<String, dynamic>, DateTime>(
                  dataSource: chartData,
                  xValueMapper: (data, _) => DateTime.parse(data['timestamp']),
                  yValueMapper: (data, _) => yMapper(data),
                  color: color,
                  width: 2.5,
                  markerSettings: MarkerSettings(
                    isVisible: true,
                    shape: DataMarkerType.circle,
                    width: 6,
                    height: 6,
                    borderColor: color,
                    color: cardColor,
                    borderWidth: 2,
                  ),
                ),
              ],
              tooltipBehavior: TooltipBehavior(
                enable: true,
                color: textPrimary,
                textStyle: const TextStyle(color: Colors.white),
              ),
              zoomPanBehavior: ZoomPanBehavior(
                enablePanning: true,
                enablePinching: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackChart() {
    if (recentCalls.isEmpty) return const SizedBox.shrink();

    final feedbackData = <DateTime, int>{};
    for (var call in recentCalls.reversed) {
      final time = DateTime.parse(call['timestamp']);
      final roundedTime = DateTime(time.year, time.month, time.day, time.hour, (time.minute ~/ 5) * 5);
      final fb = call['feedback'] as int?;
      if (fb == 1) {
        feedbackData.update(roundedTime, (v) => v + 1, ifAbsent: () => 1);
      } else if (fb == -1) {
        feedbackData.update(roundedTime, (v) => v - 1, ifAbsent: () => -1);
      }
    }

    final chartData = feedbackData.entries
        .map((e) => {'time': e.key, 'score': e.value.toDouble()})
        .toList()
      ..sort((a, b) => (a['time'] as DateTime).compareTo(b['time'] as DateTime));

    if (chartData.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.poll, size: 20, color: primaryColor),
              ),
              const SizedBox(width: 12),
              const Text(
                'User Feedback Trend',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 280,
            child: SfCartesianChart(
              plotAreaBorderWidth: 0,
              primaryXAxis: DateTimeAxis(
                dateFormat: DateFormat.Hm(),
                majorGridLines: const MajorGridLines(width: 0),
                axisLine: const AxisLine(width: 0),
                labelStyle: const TextStyle(color: textSecondary, fontSize: 11),
              ),
              primaryYAxis: NumericAxis(
                majorGridLines: MajorGridLines(width: 1, color: Colors.grey.shade200),
                axisLine: const AxisLine(width: 0),
                labelStyle: const TextStyle(color: textSecondary, fontSize: 11),
              ),
              series: <ColumnSeries<Map<String, dynamic>, DateTime>>[
                ColumnSeries<Map<String, dynamic>, DateTime>(
                  dataSource: chartData,
                  xValueMapper: (data, _) => data['time'],
                  yValueMapper: (data, _) => data['score'],
                  pointColorMapper: (data, _) =>
                  (data['score'] as double) >= 0 ? successColor : errorColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                ),
              ],
              tooltipBehavior: TooltipBehavior(
                enable: true,
                color: textPrimary,
                textStyle: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentErrors() {
    final errorCalls = recentCalls.where((call) => call['error'] != null).toList();
    errorCalls.sort((a, b) => DateTime.parse(b['timestamp']).compareTo(DateTime.parse(a['timestamp'])));

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: errorColor.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: errorColor.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: errorColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.warning_amber_rounded, size: 20, color: errorColor),
              ),
              const SizedBox(width: 12),
              const Text(
                'Recent Errors',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          errorCalls.isEmpty
              ? Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: successColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle, color: successColor),
                SizedBox(width: 12),
                Text(
                  'No errors recorded',
                  style: TextStyle(fontSize: 15, color: successColor, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          )
              : ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: errorCalls.length > 10 ? 10 : errorCalls.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final call = errorCalls[i];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: errorColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.error_outline, color: errorColor, size: 20),
                ),
                title: Text(
                  (call['input'] ?? 'Unknown input').toString().length > 60
                      ? '${(call['input'] ?? '').toString().substring(0, 60)}...'
                      : call['input'] ?? 'Unknown',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  call['error'] ?? 'Unknown error',
                  style: const TextStyle(color: errorColor, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  DateFormat('HH:mm').format(DateTime.parse(call['timestamp'])),
                  style: const TextStyle(color: textSecondary, fontSize: 12),
                ),
                onTap: () => showCallDetails(call),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final avgLatency = (summary['avg_latency'] ?? 0).toDouble();
    final totalCalls = (summary['total_calls'] ?? 0) as num;
    final errorRate = totalCalls > 0 ? ((summary['errors'] ?? 0) / totalCalls * 100).toStringAsFixed(1) : '0';

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: cardColor,
        title: const Row(
          children: [
            Icon(Icons.dashboard, color: primaryColor, size: 28),
            SizedBox(width: 12),
            Text(
              'LLM Observability',
              style: TextStyle(
                color: textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded, color: textPrimary),
            onPressed: exportToCsv,
            tooltip: 'Export CSV',
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: textPrimary),
                onPressed: fetchData,
                tooltip: 'Refresh',
              ),
              if (isLoading && recentCalls.isNotEmpty)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: primaryColor),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                const Text(
                  'Live',
                  style: TextStyle(fontSize: 13, color: textSecondary, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
      body: isLoading && recentCalls.isEmpty
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: primaryColor),
            SizedBox(height: 16),
            Text('Loading dashboard...', style: TextStyle(color: textSecondary)),
          ],
        ),
      )
          : errorMessage.isNotEmpty
          ? Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: errorColor.withOpacity(0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: errorColor, size: 60),
              const SizedBox(height: 16),
              Text(
                errorMessage,
                style: const TextStyle(color: errorColor),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: fetchData,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
      )
          : RefreshIndicator(
        onRefresh: fetchData,
        color: primaryColor,
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
                  decoration: BoxDecoration(
                    color: errorColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: errorColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: errorColor, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'High Average Latency: ${avgLatency.toStringAsFixed(2)}s',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: errorColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if ((summary['errors'] ?? 0) > 0)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: warningColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: warningColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: warningColor, size: 24),
                      const SizedBox(width: 12),
                      Text(
                        '${summary['errors']} Error(s) Detected',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: warningColor,
                        ),
                      ),
                    ],
                  ),
                ),

              // Summary Metrics
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2,
                childAspectRatio: 1.0,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                children: [
                  _buildMetricCard('Total Calls', summary['total_calls'] ?? 0, Icons.bar_chart_rounded, color: primaryColor),
                  _buildMetricCard('Avg Latency', '${avgLatency.toStringAsFixed(2)}s', Icons.timer,
                      color: avgLatency > 5 ? errorColor : avgLatency > 2 ? warningColor : successColor),
                  _buildMetricCard('Total Tokens', summary['total_tokens'] ?? 0, Icons.token, color: primaryColor),
                  _buildMetricCard('Error Rate', '$errorRate%', Icons.error_outline,
                      color: (summary['errors'] ?? 0) > 0 ? warningColor : successColor),
                  _buildMetricCard('Good Feedback', summary['good_feedback'] ?? 0, Icons.thumb_up, color: successColor),
                  _buildMetricCard('Bad Feedback', summary['bad_feedback'] ?? 0, Icons.thumb_down, color: errorColor),
                ],
              ),

              const SizedBox(height: 24),

              // Charts
              _buildChart(
                title: 'Token Usage Over Time',
                yMapper: (data) => (data['total_tokens'] ?? 0).toDouble(),
                color: primaryColor,
              ),
              const SizedBox(height: 24),
              _buildChart(
                title: 'Latency Over Time',
                yMapper: (data) => (data['latency_sec'] ?? 0).toDouble(),
                color: warningColor,
              ),
              const SizedBox(height: 24),
              _buildFeedbackChart(),
              const SizedBox(height: 24),

              // Recent Errors
              _buildRecentErrors(),
              const SizedBox(height: 24),

              // Recent Calls
              Text(
                'Recent Calls (Latest 20)',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: recentCalls.length > 20 ? 20 : recentCalls.length,
                itemBuilder: (context, index) {
                  final call = recentCalls[recentCalls.length - 1 - index];
                  final feedback = call['feedback'];

                  return Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      onTap: () => showCallDetails(call),
                      title: Text(
                        (call['input'] ?? 'No input').toString().length > 70
                            ? '${(call['input'] ?? '').substring(0, 70)}...'
                            : call['input'] ?? 'No input',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Latency: ${call['latency_sec'] ?? 'N/A'}s • Tokens: ${call['total_tokens'] ?? 'N/A'} • '
                              'Feedback: ${feedback == 1 ? '👍 Good' : feedback == -1 ? '👎 Bad' : '— None'}',
                          style: TextStyle(color: textSecondary),
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (call['error'] != null)
                            const Icon(Icons.error, color: errorColor, size: 20),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_ios, size: 16, color: textSecondary),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}