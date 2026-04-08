import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../config/user_theme.dart';

class WeeklyActivityChart extends StatelessWidget {
  final List<int> receivedData;
  final List<int> deliveredData;
  final List<String>? labels;

  const WeeklyActivityChart({
    super.key,
    required this.receivedData,
    required this.deliveredData,
    this.labels,
  });

  @override
  Widget build(BuildContext context) {
    // Determine the max value for Y-axis scaling
    int maxVal = 0;
    for (var val in receivedData) if (val > maxVal) maxVal = val;
    for (var val in deliveredData) if (val > maxVal) maxVal = val;
    
    // Scale Y-axis to nearest multiple of 7 or at least 28 as in screenshot
    double yMax = (maxVal < 28) ? 28 : (maxVal + 7 - (maxVal % 7)).toDouble();

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: UserTheme.backgroundCard,
        borderRadius: BorderRadius.circular(UserTheme.radiusXL),
        boxShadow: [
          BoxShadow(
            color: UserTheme.primaryOrange.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: UserTheme.textMuted.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 17), // Precise alignment with Y-Axis Labels
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: UserTheme.primaryOrange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.bar_chart_rounded, color: UserTheme.primaryOrange, size: 20),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Weekly activity',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: UserTheme.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 1.5,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: yMax,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    tooltipBgColor: Colors.white,
                    tooltipRoundedRadius: 8,
                    tooltipPadding: const EdgeInsets.all(12),
                    tooltipBorder: BorderSide(color: Colors.grey.shade200),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      String weekDay = _getWeekDay(group.x);
                      return BarTooltipItem(
                        '$weekDay\n',
                        const TextStyle(
                          color: UserTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        children: [
                          TextSpan(
                            text: 'received : ${receivedData[group.x]}\n',
                            style: const TextStyle(
                              color: UserTheme.accentAmberDark,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextSpan(
                            text: 'delivered : ${deliveredData[group.x]}',
                            style: const TextStyle(
                              color: UserTheme.sunsetEnd,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            _getWeekDay(value.toInt()),
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      },
                      reservedSize: 30,
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: 7,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toInt().toString(),
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 11,
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 7,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: Colors.grey.withOpacity(0.1),
                      strokeWidth: 1,
                      dashArray: [5, 5],
                    );
                  },
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(7, (i) {
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: receivedData[i].toDouble(),
                        color: UserTheme.accentAmberDark,
                        width: 8,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                      BarChartRodData(
                        toY: deliveredData[i].toDouble(),
                        color: UserTheme.gradientPink,
                        width: 8,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendItem('received', UserTheme.accentAmberDark),
              const SizedBox(width: 20),
              _buildLegendItem('delivered', UserTheme.gradientPink),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[700],
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  String _getWeekDay(int value) {
    if (labels != null && value >= 0 && value < labels!.length) {
      return labels![value];
    }
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    if (value >= 0 && value < 7) return days[value];
    return '';
  }
}
