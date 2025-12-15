import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/api.dart';

class Dashboard extends StatefulWidget {
  @override
  _DashboardState createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  int totalCalls = 0;
  int errors = 0;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  void loadData() async {
    final data = await ApiService.getSummary();
    setState(() {
      totalCalls = data["total_calls"];
      errors = data["error_rate"];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("LLM Observability Dashboard")),
      body: Column(
        children: [
          Text("Total Calls: $totalCalls"),
          Text("Errors: $errors"),
          SizedBox(height: 20),
          Expanded(
            child: LineChart(
              LineChartData(
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      FlSpot(1, 10),
                      FlSpot(2, 30),
                      FlSpot(3, 20),
                    ],
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
