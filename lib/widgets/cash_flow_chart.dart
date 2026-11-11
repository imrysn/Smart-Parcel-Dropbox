import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../config/user_theme.dart';

class CashFlowTrendPoint {
  final String date;
  final double revenue;
  final double expense;
  final double net;

  CashFlowTrendPoint({
    required this.date,
    required this.revenue,
    required this.expense,
    required this.net,
  });

  factory CashFlowTrendPoint.fromMap(Map<String, dynamic> map) {
    return CashFlowTrendPoint(
      date: map['date']?.toString() ?? '',
      revenue: (map['revenue'] as num?)?.toDouble() ?? 0.0,
      expense: (map['expense'] as num?)?.toDouble() ?? 0.0,
      net: (map['net'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class CashFlowChart extends StatefulWidget {
  final List<CashFlowTrendPoint> trends;
  final double dailyVelocity;
  final double forecast30DaysNet;
  final int pipelineCount;
  final double pipelineProjectedRevenue;

  const CashFlowChart({
    super.key,
    required this.trends,
    required this.dailyVelocity,
    required this.forecast30DaysNet,
    required this.pipelineCount,
    required this.pipelineProjectedRevenue,
  });

  @override
  State<CashFlowChart> createState() => _CashFlowChartState();
}

class _CashFlowChartState extends State<CashFlowChart> {
  int _selectedMode = 0; // 0 = Cash Balance, 1 = Revenue vs Expenses

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (widget.trends.isEmpty) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        child: Text(
          'No transaction history available yet',
          style: TextStyle(color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mode Selector Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                _buildModePill(0, 'Net Cash Flow', Icons.show_chart_rounded),
                const SizedBox(width: 8),
                _buildModePill(1, 'Rev vs Exp', Icons.compare_arrows_rounded),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: UserTheme.statusSuccess.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: UserTheme.statusSuccess.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bolt_rounded, size: 14, color: UserTheme.statusSuccess),
                  const SizedBox(width: 4),
                  Text(
                    '₱${widget.dailyVelocity.toStringAsFixed(0)}/day',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: UserTheme.statusSuccess,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Main fl_chart LineChart Container
        SizedBox(
          height: 180,
          child: LineChart(
            _selectedMode == 0 ? _buildNetCashChartData(isDark) : _buildRevExpenseChartData(isDark),
          ),
        ),
        const SizedBox(height: 16),

        // 30-Day Predictive Forecast Badge
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [Colors.purple.shade900.withOpacity(0.4), Colors.indigo.shade900.withOpacity(0.3)]
                  : [Colors.purple.shade50, Colors.indigo.shade50],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.purpleAccent.withOpacity(0.3) : Colors.purple.withOpacity(0.2),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: UserTheme.primaryOrange.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.auto_graph_rounded, color: UserTheme.primaryOrange, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '30-Day Predictive Cash Forecast',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Includes ${widget.pipelineCount} active craft tasks (Projected +₱${widget.pipelineProjectedRevenue.toStringAsFixed(0)})',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '₱${widget.forecast30DaysNet.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: widget.forecast30DaysNet >= 0 ? UserTheme.statusSuccess : UserTheme.statusError,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModePill(int mode, String title, IconData icon) {
    final isSelected = _selectedMode == mode;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () => setState(() => _selectedMode = mode),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? UserTheme.primaryOrange
              : (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : (isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted)),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: isSelected ? Colors.white : (isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  LineChartData _buildNetCashChartData(bool isDark) {
    final spots = List.generate(widget.trends.length, (i) {
      return FlSpot(i.toDouble(), widget.trends[i].net);
    });

    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final padding = (maxY - minY) == 0 ? 10.0 : (maxY - minY) * 0.2;

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (val) => FlLine(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
          strokeWidth: 1,
        ),
      ),
      titlesData: const FlTitlesData(
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      minX: 0,
      maxX: (widget.trends.length - 1).toDouble(),
      minY: minY - padding,
      maxY: maxY + padding,
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (touchedSpots) {
            return touchedSpots.map((spot) {
              final idx = spot.x.toInt();
              if (idx >= 0 && idx < widget.trends.length) {
                final pt = widget.trends[idx];
                return LineTooltipItem(
                  '${pt.date}\nNet: ₱${pt.net.toStringAsFixed(0)}',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                );
              }
              return null;
            }).toList();
          },
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          curveSmoothness: 0.35,
          color: UserTheme.primaryOrange,
          barWidth: 2.5,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                UserTheme.primaryOrange.withOpacity(0.25),
                UserTheme.primaryOrange.withOpacity(0.0),
              ],
            ),
          ),
        ),
      ],
    );
  }

  LineChartData _buildRevExpenseChartData(bool isDark) {
    final revSpots = List.generate(widget.trends.length, (i) => FlSpot(i.toDouble(), widget.trends[i].revenue));
    final expSpots = List.generate(widget.trends.length, (i) => FlSpot(i.toDouble(), widget.trends[i].expense));

    double maxY = 100;
    for (var t in widget.trends) {
      if (t.revenue > maxY) maxY = t.revenue;
      if (t.expense > maxY) maxY = t.expense;
    }

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (val) => FlLine(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
          strokeWidth: 1,
        ),
      ),
      titlesData: const FlTitlesData(
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      minX: 0,
      maxX: (widget.trends.length - 1).toDouble(),
      minY: 0,
      maxY: maxY * 1.2,
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (touchedSpots) {
            return touchedSpots.map((spot) {
              final idx = spot.x.toInt();
              if (idx >= 0 && idx < widget.trends.length) {
                final pt = widget.trends[idx];
                final isRev = spot.bar.color == UserTheme.statusSuccess;
                return LineTooltipItem(
                  isRev ? 'Rev: ₱${pt.revenue.toStringAsFixed(0)}' : 'Exp: ₱${pt.expense.toStringAsFixed(0)}',
                  TextStyle(
                    color: isRev ? UserTheme.statusSuccess : UserTheme.statusError,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                );
              }
              return null;
            }).toList();
          },
        ),
      ),
      lineBarsData: [
        // Revenue Line (Green)
        LineChartBarData(
          spots: revSpots,
          isCurved: true,
          curveSmoothness: 0.35,
          color: UserTheme.statusSuccess,
          barWidth: 2.2,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
        ),
        // Expense Line (Red)
        LineChartBarData(
          spots: expSpots,
          isCurved: true,
          curveSmoothness: 0.35,
          color: UserTheme.statusError,
          barWidth: 2.2,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
        ),
      ],
    );
  }
}
