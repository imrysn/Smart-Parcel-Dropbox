import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../config/user_theme.dart';

class WeeklyActivityChart extends StatelessWidget {
  final List<int> receivedData;
  final List<int> deliveredData;

  const WeeklyActivityChart({
    super.key,
    required this.receivedData,
    required this.deliveredData,
  });

  @override
  Widget build(BuildContext context) {
    // Determine the max value for Y-axis scaling
    int maxVal = 0;
    for (var val in receivedData) if (val > maxVal) maxVal = val;
    for (var val in deliveredData) if (val > maxVal) maxVal = val;
    
    // Scale Y-axis - more sensitive to low data (if maxVal is low, don't floor at 28)
    double yMax;
    if (maxVal == 0) {
      yMax = 5.0;
    } else if (maxVal <= 5) {
      yMax = 5.0;
    } else if (maxVal < 20) {
      yMax = 20.0;
    } else {
      yMax = (maxVal + 7 - (maxVal % 7)).toDouble();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 17), // Precise alignment with Y-Axis Labels
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: UserTheme.primaryOrange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.bar_chart_rounded, color: UserTheme.primaryOrange, size: 16),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Weekly activity',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: UserTheme.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          AspectRatio(
            aspectRatio: 2.2,
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
                              color: Colors.grey[500],
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        );
                      },
                      reservedSize: 28,
                    ),
                  ),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(7, (i) {
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: receivedData[i].toDouble(),
                        color: UserTheme.accentAmberDark,
                        width: 6,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      BarChartRodData(
                        toY: deliveredData[i].toDouble(),
                        color: UserTheme.gradientPink,
                        width: 6,
                        borderRadius: BorderRadius.circular(3),
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
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    if (value >= 0 && value < 7) return days[value];
    return '';
  }
}
