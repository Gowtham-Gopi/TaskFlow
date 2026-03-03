import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TodoApp());
}

class TodoApp extends StatelessWidget {
  const TodoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TaskFlow',
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.white,
        textTheme: GoogleFonts.poppinsTextTheme(Theme.of(context).textTheme),
      ),
      home: const TodoHome(),
    );
  }
}

class Task {
  int? id;
  String title;
  bool isCompleted;
  DateTime? dueDate;

  Task({this.id, required this.title, this.isCompleted = false, this.dueDate});

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'isCompleted': isCompleted ? 1 : 0,
      'dueDate': dueDate?.toIso8601String(),
    };
  }

  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      id: map['id'],
      title: map['title'],
      isCompleted: map['isCompleted'] == 1,
      dueDate: map['dueDate'] != null ? DateTime.parse(map['dueDate']) : null,
    );
  }
}

class DatabaseHelper {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = p.join(await getDatabasesPath(), 'taskflow.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) {
        return db.execute(
          'CREATE TABLE tasks(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, isCompleted INTEGER, dueDate TEXT)',
        );
      },
    );
  }

  Future<int> insertTask(Task task) async {
    Database db = await database;
    return await db.insert('tasks', task.toMap());
  }

  Future<List<Task>> getTasks() async {
    Database db = await database;
    List<Map<String, dynamic>> maps = await db.query('tasks');
    return List.generate(maps.length, (i) => Task.fromMap(maps[i]));
  }

  Future<int> updateTask(Task task) async {
    Database db = await database;
    return await db.update(
      'tasks',
      task.toMap(),
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }

  Future<int> deleteTask(int id) async {
    Database db = await database;
    return await db.delete(
      'tasks',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

class TodoHome extends StatefulWidget {
  const TodoHome({super.key});

  @override
  State<TodoHome> createState() => _TodoHomeState();
}

class _TodoHomeState extends State<TodoHome> {
  List<Task> _tasks = [];
  final DatabaseHelper _dbHelper = DatabaseHelper();
  late AudioPlayer _audioPlayer;
  Uint8List? _taskAddedSoundBytes;
  Uint8List? _taskCompletedSoundBytes;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _loadSounds();
    _refreshTasks();
  }

  Future<void> _refreshTasks() async {
    final tasks = await _dbHelper.getTasks();
    setState(() {
      _tasks = tasks;
      _sortTasks();
    });
  }

  void _sortTasks() {
     _tasks.sort((a, b) => a.isCompleted == b.isCompleted ? 0 : (a.isCompleted ? 1 : -1));
  }

  Future<void> _loadSounds() async {
    try {
      _taskAddedSoundBytes = (await rootBundle.load('assets/sounds/task_added.mp3')).buffer.asUint8List();
      _taskCompletedSoundBytes = (await rootBundle.load('assets/sounds/task_completed.mp3')).buffer.asUint8List();
    } catch (e) {
      // handle exception if sound files are not found
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  void _playSound(Uint8List? soundBytes) {
    if (soundBytes != null) {
      _audioPlayer.play(BytesSource(soundBytes));
    }
  }

  Future<void> _addTask(String title, DateTime? dueDate) async {
    if (title.isNotEmpty) {
      Task newTask = Task(title: title, dueDate: dueDate ?? DateTime.now());
      await _dbHelper.insertTask(newTask);
      _playSound(_taskAddedSoundBytes);
      _refreshTasks();
    }
  }

  Future<void> _toggleTaskCompletion(Task task) async {
    task.isCompleted = !task.isCompleted;
    await _dbHelper.updateTask(task);
    if (task.isCompleted) {
      _playSound(_taskCompletedSoundBytes);
    }
    _refreshTasks();
  }

  Future<void> _deleteTask(Task task) async {
    if (task.id != null) {
      await _dbHelper.deleteTask(task.id!);
      _refreshTasks();
    }
  }

  String _getDueDateText(DateTime? date) {
    if (date == null) {
      return 'Add Due Date';
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final dueDate = DateTime(date.year, date.month, date.day);

    if (dueDate == today) {
      return 'Today';
    } else if (dueDate == tomorrow) {
      return 'Tomorrow';
    } else {
      return DateFormat('MMM dd').format(date);
    }
  }

  void _showAddTaskDialog() {
    final TextEditingController textController = TextEditingController();
    DateTime? selectedDate = DateTime.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final Function(String) submitTask = (String value) {
            if (value.isNotEmpty) {
              _addTask(value, selectedDate);
              textController.clear();
              setModalState(() {
                selectedDate = DateTime.now();
              });
            }
          };

          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 20,
                right: 20,
                top: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: textController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Enter task title',
                    border: InputBorder.none,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.send),
                      iconSize: 30.0,
                      onPressed: () => submitTask(textController.text),
                    ),
                  ),
                  onSubmitted: (value) => submitTask(value),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2101));
                    if (picked != null) {
                      setModalState(() {
                        selectedDate = picked;
                      });
                    }
                  },
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(_getDueDateText(selectedDate)),
                )
              ],
            ),
          );
        },
      ),
    );
  }

  void _showEditTaskDialog(Task task) {
    final TextEditingController textController = TextEditingController(text: task.title);
    DateTime? selectedDate = task.dueDate;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final Function() submitChanges = () async {
            if (textController.text.isNotEmpty) {
              task.title = textController.text;
              task.dueDate = selectedDate;
              await _dbHelper.updateTask(task);
              Navigator.pop(context);
              _refreshTasks();
            }
          };

          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 20,
                right: 20,
                top: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Edit Task', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                TextField(
                  controller: textController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Enter task title',
                    border: InputBorder.none,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.send),
                      iconSize: 30.0,
                      onPressed: submitChanges,
                    ),
                  ),
                  onSubmitted: (_) => submitChanges(),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2101));
                    if (picked != null) {
                      setModalState(() {
                        selectedDate = picked;
                      });
                    }
                  },
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(_getDueDateText(selectedDate)),
                )
              ],
            ),
          );
        },
      ),
    );
  }

  Color _getDueDateColor(DateTime? date) {
    if (date == null) {
      return Colors.grey;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDate = DateTime(date.year, date.month, date.day);

    if (dueDate.isBefore(today)) {
      return Colors.red;
    } else {
      return Colors.green;
    }
  }

  Widget _buildTaskCard(Task task, {Key? key}) {
    return Card(
      key: key,
      color: Colors.white,
      elevation: 4.0,
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: ListTile(
        onTap: task.isCompleted ? null : () => _showEditTaskDialog(task),
        leading: Checkbox(
          activeColor: Colors.green,
          shape: const CircleBorder(),
          value: task.isCompleted,
          onChanged: (value) => _toggleTaskCompletion(task),
        ),
        title: Text(
          task.title,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            decoration: task.isCompleted
                ? TextDecoration.lineThrough
                : TextDecoration.none,
          ),
        ),
        subtitle: task.dueDate != null
            ? Text(
                _getDueDateText(task.dueDate),
                style: TextStyle(color: _getDueDateColor(task.dueDate)),
              )
            : null,
        trailing: IconButton(
          icon: const Icon(Icons.delete, color: Colors.red),
          onPressed: () => _deleteTask(task),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final incompleteTasks = _tasks.where((task) => !task.isCompleted).toList();
    final completedTasks = _tasks.where((task) => task.isCompleted).toList();

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 80,
        title: Image.asset(
          'lib/TaskFlow Logo.png',
          height: 50,
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 24.0, bottom: 8.0),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 8.0),
            child: Text(
              'Tasks',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          if (incompleteTasks.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: Text('No tasks pending'),
              ),
            )
          else
            ReorderableListView.builder(
              itemCount: incompleteTasks.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (context, index) {
                final task = incompleteTasks[index];
                return _buildTaskCard(task, key: ValueKey(task.id ?? task.title));
              },
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (oldIndex < newIndex) {
                    newIndex -= 1;
                  }
                  final task = incompleteTasks.removeAt(oldIndex);
                  incompleteTasks.insert(newIndex, task);
                });
              },
              proxyDecorator: (widget, index, animation) {
                return Material(
                  elevation: 8.0,
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(12.0),
                  child: widget,
                );
              },
            ),
          const Divider(height: 32.0, thickness: 1.0, indent: 16.0, endIndent: 16.0),
          Padding(
            padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 8.0),
            child: Text(
              'Completed',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          if (completedTasks.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: Text('No tasks completed'),
              ),
            )
          else
            ListView.builder(
              itemCount: completedTasks.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (context, index) {
                return _buildTaskCard(completedTasks[index]);
              },
            ),
          if (completedTasks.isNotEmpty)
            const Divider(height: 32.0, thickness: 1.0, indent: 16.0, endIndent: 16.0),
          const SizedBox(height: 72.0),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: SizedBox(
        width: 112.0,
        height: 56.0,
        child: FloatingActionButton(
          backgroundColor: Colors.lightBlueAccent,
          onPressed: _showAddTaskDialog,
          tooltip: 'Add Task',
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28.0),
          ),
          foregroundColor: Colors.white,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
