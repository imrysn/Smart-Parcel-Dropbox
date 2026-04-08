import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class MiniSparkline extends StatelessWidget {
  final List<int> data;
  final Color color;

  const MiniSparkline({
    super.key,
    required this.data,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();

    // Use only real data points
    final List<double> displayData = data.map((e) => e.toDouble()).toList();

    double maxVal = displayData.reduce((a, b) => a > b ? a : b);
    double minVal = displayData.reduce((a, b) => a < b ? a : b);
    
    // Determine Y-axis range
    double yMin, yMax;
    if (maxVal == 0 && minVal == 0) {
      // If everything is zero, show a flat line in the middle of the box
      yMin = -1.0;
      yMax = 3.0; // Higher max to keep the line at the lower end
    } else {
      // Add some padding to the Y axis to prevent clipping and keep it centered
      double range = maxVal - minVal;
      double yPadding = range == 0 ? 1.0 : range * 0.3;
      yMin = minVal - yPadding;
      yMax = maxVal + yPadding;
    }

    final spots = List.generate(displayData.length, (i) {
      return FlSpot(i.toDouble(), displayData[i]);
    });

    return SizedBox(
      height: 22,
      width: 45,
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: (displayData.length - 1).toDouble(),
          minY: yMin,
          maxY: yMax,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.5,
              color: color,
              barWidth: 1.8,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    color.withOpacity(0.15),
                    color.withOpacity(0.0),
                  ],
                ),
              ),
              shadow: Shadow(
                color: color.withOpacity(0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
