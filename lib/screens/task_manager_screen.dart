import 'package:flutter/material.dart';
import '../config/user_theme.dart';
import '../widgets/user_ui.dart';
import '../widgets/task_pipeline_card.dart';
import '../models/task_model.dart';
import '../services/task_service.dart';
import 'financial_screen.dart';

/// Task Manager Screen — All-in-One Craft Business Pipeline & Financials
class TaskManagerScreen extends StatefulWidget {
  const TaskManagerScreen({super.key});

  @override
  State<TaskManagerScreen> createState() => _TaskManagerScreenState();
}

class _TaskManagerScreenState extends State<TaskManagerScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TaskService _taskService = TaskService();
  bool _isLoading = false;
  int _viewMode = 0; // 0 = Craft Kanban, 1 = Financial Ledger

  Map<String, List<TaskModel>> _tasksGrouped = {
    'INQUIRY': [],
    'CRAFTING': [],
    'READY_FOR_BOX': [],
    'SHIPPED': [],
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadTasks();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    setState(() => _isLoading = true);
    try {
      final grouped = await _taskService.fetchGroupedTasks();
      if (mounted) {
        setState(() {
          _tasksGrouped = grouped;
        });
      }
    } catch (e) {
      debugPrint('Error loading tasks: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _moveTaskStage(TaskModel task, String newStage, {bool openDoor = false}) async {
    // 1. OPTIMISTIC LOCAL MUTATION
    final backupGrouped = Map<String, List<TaskModel>>.from(
      _tasksGrouped.map((k, v) => MapEntry(k, List<TaskModel>.from(v))),
    );

    setState(() {
      _tasksGrouped[task.stage]?.removeWhere((t) => t.id == task.id);
      final updatedTask = task.copyWith(stage: newStage);
      _tasksGrouped[newStage] = [updatedTask, ...(_tasksGrouped[newStage] ?? [])];
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Task moved to $newStage!'),
          backgroundColor: UserTheme.statusSuccess,
          duration: const Duration(seconds: 1),
        ),
      );
    }

    // 2. ASYNC BACKGROUND SYNC
    try {
      await _taskService.updateTaskStage(taskId: task.id, newStage: newStage, openDoor: openDoor);
    } catch (e) {
      // 3. ROLLBACK ON ERROR
      if (mounted) {
        setState(() {
          _tasksGrouped = backupGrouped;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Network error. Reverted task move: $e'), backgroundColor: UserTheme.statusError),
        );
      }
    }
  }

  Future<void> _deleteTask(TaskModel task) async {
    // 1. OPTIMISTIC LOCAL MUTATION
    final backupGrouped = Map<String, List<TaskModel>>.from(
      _tasksGrouped.map((k, v) => MapEntry(k, List<TaskModel>.from(v))),
    );

    setState(() {
      _tasksGrouped[task.stage]?.removeWhere((t) => t.id == task.id);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task deleted'), backgroundColor: UserTheme.statusSuccess),
      );
    }

    // 2. ASYNC BACKGROUND SYNC
    try {
      await _taskService.deleteTask(task.id);
    } catch (e) {
      // 3. ROLLBACK ON ERROR
      if (mounted) {
        setState(() {
          _tasksGrouped = backupGrouped;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Network error. Restored deleted task: $e'), backgroundColor: UserTheme.statusError),
        );
      }
    }
  }

  void _showAddTaskDialog() {
    final titleController = TextEditingController();
    final customerNameController = TextEditingController();
    final phoneController = TextEditingController();
    String selectedPlatform = 'CUSTOM';
    String selectedStage = 'INQUIRY';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Craft Task / Lead'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Task Title / Product Item',
                    hintText: 'e.g. Custom Resin Coaster Set',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: customerNameController,
                  decoration: const InputDecoration(
                    labelText: 'Customer Name',
                    hintText: 'e.g. Sarah Smith',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Customer Phone (Optional)',
                    hintText: 'e.g. 60123456789',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedPlatform,
                  decoration: const InputDecoration(labelText: 'Shop / Platform Source'),
                  items: ['CUSTOM', 'SHOPEE', 'TIKTOK', 'INSTAGRAM'].map((p) {
                    return DropdownMenuItem(value: p, child: Text(p));
                  }).toList(),
                  onChanged: (val) => setDialogState(() => selectedPlatform = val!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedStage,
                  decoration: const InputDecoration(labelText: 'Initial Stage'),
                  items: ['INQUIRY', 'CRAFTING', 'READY_FOR_BOX'].map((s) {
                    return DropdownMenuItem(value: s, child: Text(s));
                  }).toList(),
                  onChanged: (val) => setDialogState(() => selectedStage = val!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('CANCEL')),
            ElevatedButton(
              onPressed: () async {
                if (titleController.text.trim().isEmpty) return;
                Navigator.of(context).pop();
                try {
                  await _taskService.createTask(
                    title: titleController.text.trim(),
                    stage: selectedStage,
                    platform: selectedPlatform,
                    customerName: customerNameController.text.trim(),
                    customerPhone: phoneController.text.trim(),
                  );
                  _loadTasks();
                } catch (e) {
                  debugPrint('Error creating task: $e');
                }
              },
              child: const Text('CREATE TASK'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: UserUi.pageBackground(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Row(
            children: [
              Text(
                _viewMode == 0 ? 'Craft Task Pipeline' : 'Business Financials',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                ),
              ),
            ],
          ),
          actions: [
            // Mode Switcher Pill: Tasks vs Financials
            Container(
              margin: const EdgeInsets.only(right: 16),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => setState(() => _viewMode = 0),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _viewMode == 0 ? UserTheme.primaryOrange : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Tasks',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _viewMode == 0 ? Colors.white : (isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted),
                        ),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _viewMode = 1),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _viewMode == 1 ? UserTheme.statusSuccess : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '₱ Ledger',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _viewMode == 1 ? Colors.white : (isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          bottom: _viewMode == 0
              ? TabBar(
                  controller: _tabController,
                  isScrollable: false,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                  indicatorColor: UserTheme.primaryOrange,
                  indicatorWeight: 3,
                  labelColor: UserTheme.primaryOrange,
                  unselectedLabelColor: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                  tabs: [
                    Tab(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '📥 Inquiries (${_tasksGrouped['INQUIRY']?.length ?? 0})',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                      ),
                    ),
                    Tab(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '🎨 Crafting (${_tasksGrouped['CRAFTING']?.length ?? 0})',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                      ),
                    ),
                    Tab(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '📦 Ready Box (${_tasksGrouped['READY_FOR_BOX']?.length ?? 0})',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                      ),
                    ),
                    Tab(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '🚚 Shipped (${_tasksGrouped['SHIPPED']?.length ?? 0})',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                )
              : null,
        ),
        floatingActionButton: _viewMode == 0
            ? Padding(
                padding: const EdgeInsets.only(bottom: 80),
                child: FloatingActionButton.extended(
                  onPressed: _showAddTaskDialog,
                  backgroundColor: UserTheme.primaryOrange,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New Task / Lead'),
                ),
              )
            : null,
        body: _viewMode == 0
            ? RefreshIndicator(
                onRefresh: _loadTasks,
                color: UserTheme.primaryOrange,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildStageList('INQUIRY'),
                    _buildStageList('CRAFTING'),
                    _buildStageList('READY_FOR_BOX'),
                    _buildStageList('SHIPPED'),
                  ],
                ),
              )
            : const FinancialScreen(),
      ),
    );
  }

  Widget _buildStageList(String stageKey) {
    final list = _tasksGrouped[stageKey] ?? [];

    if (_isLoading && list.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: UserTheme.primaryOrange));
    }

    if (list.isEmpty) {
      return UserUi.emptyState(
        context,
        icon: Icons.checklist_rounded,
        title: 'No tasks in this stage',
        subtitle: 'Tap "+ New Task / Lead" below to add custom orders or leads.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 100),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final task = list[index];
        return TaskPipelineCard(
          task: task,
          onMoveStage: (newStage, {bool openDoor = false}) => _moveTaskStage(task, newStage, openDoor: openDoor),
          onDelete: () => _deleteTask(task),
        );
      },
    );
  }
}
