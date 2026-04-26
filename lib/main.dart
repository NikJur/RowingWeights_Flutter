import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'database_helper.dart';

void main() {
  runApp(const RowingWeightsApp());
}

class RowingWeightsApp extends StatelessWidget {
  const RowingWeightsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RowingWeights',
      debugShowCheckedModeBanner: false,
      // Define official brand colours globally
      theme: ThemeData(
        primaryColor: const Color(0xFF25476D), // CoxOrb Blue
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF25476D),
          primary: const Color(0xFF25476D),
          secondary: const Color(0xFFF08118), // CoxOrb Orange
        ),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

/// The Root Widget: Manages the Bottom Navigation Bar and active screen
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  // The three screens managed by the navigation bar
  final List<Widget> _screens = const [
    LogScreen(),
    HistoryScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        selectedItemColor: Theme.of(context).colorScheme.secondary, // Highlights active tab in Orange
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.edit),
            label: 'Log Weight',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.show_chart),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

/// TAB 1: The Log Screen
/// Manages the state and user inputs for logging a daily weight entry.
class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  // Controller reads the text entered into the weight text field
  final TextEditingController _weightController = TextEditingController();

  // State variable stores the currently selected date, defaulting to today
  DateTime _selectedDate = DateTime.now();

  /// Displays a calendar dialog and updates the state with the chosen date.
  Future<void> _pickDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(), // Prevents selecting future dates
    );

    if (picked != null && picked != _selectedDate) {
      // Triggers a UI rebuild to show the newly selected date
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  /// Validates the input text and prepares the weight data for database insertion.
  void _saveWeight() {
    final String weightText = _weightController.text;

    if (weightText.isEmpty) {
      // Shows an error banner if the field is empty
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid weight.')),
      );
      return;
    }

    final double? parsedWeight = double.tryParse(weightText);

    if (parsedWeight == null) {
      // Shows an error banner if the input is not a valid number
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid format. Use numbers only (e.g., 75.5).')),
      );
      return;
    }

    // Prints the validated data to the debug console (Database logic goes here later)
    debugPrint('Ready to save to SQLite: Date: ${_selectedDate.toIso8601String()}, Weight: $parsedWeight kg');

    // Shows a success message to the user
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved $parsedWeight kg for ${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}'),
        backgroundColor: Colors.green,
      ),
    );

    // Clears the input field after successful submission
    _weightController.clear();
  }

  // Cleans up the controller from memory when the screen is destroyed
  @override
  void dispose() {
    _weightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Daily Weight', style: TextStyle(color: Colors.white)),
        backgroundColor: Theme.of(context).primaryColor,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Date Selector Button
            OutlinedButton.icon(
              onPressed: () => _pickDate(context),
              icon: const Icon(Icons.calendar_today),
              label: Text('Date: ${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            const SizedBox(height: 24),

            // Weight Input Field
            TextField(
              controller: _weightController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Enter weight (e.g., 75.5)',
                suffixText: 'kg',
              ),
            ),
            const SizedBox(height: 24),

            // Save Button
            ElevatedButton(
              onPressed: _saveWeight,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.secondary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(60),
              ),
              child: const Text('Save Weight', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

/// TAB 2: The History Screen
/// Displays the historical weight data on an interactive line chart.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _weightData = [];
  List<FlSpot> _chartSpots = [];
  double _minY = 0;
  double _maxY = 100;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  /// Fetches data from SQLite and recalculates the chart boundaries.
  Future<void> _refreshData() async {
    final data = await DatabaseHelper.instance.fetchAllWeights();

    List<FlSpot> spots = [];
    double currentMinY = 1000;
    double currentMaxY = 0;

    for (int i = 0; i < data.length; i++) {
      final double weight = data[i]['weight'];

      if (weight < currentMinY) currentMinY = weight;
      if (weight > currentMaxY) currentMaxY = weight;

      spots.add(FlSpot(i.toDouble(), weight));
    }

    setState(() {
      _weightData = data;
      _chartSpots = spots;
      _minY = currentMinY == 1000 ? 0 : currentMinY - 5;
      _maxY = currentMaxY == 0 ? 100 : currentMaxY + 5;
      _isLoading = false;
    });
  }

  /// Prompts the user to confirm deletion, then removes the data from SQLite.
  Future<void> _confirmDelete(int id, double weight) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Entry?'),
          content: Text('Are you sure you want to delete the entry for $weight kg?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await DatabaseHelper.instance.deleteWeight(id);
      _refreshData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Entry deleted.'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  /// Displays a dialog to modify or delete the selected data point.
  Future<void> _showEditDialog(Map<String, dynamic> item) async {
    final TextEditingController editController = TextEditingController(text: item['weight'].toString());
    final DateTime date = DateTime.parse(item['date']);

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Edit Entry: ${date.day}/${date.month}'),
          content: TextField(
            controller: editController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              suffixText: 'kg',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _confirmDelete(item['id'], item['weight']);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final double? newWeight = double.tryParse(editController.text);
                if (newWeight != null) {
                  await DatabaseHelper.instance.updateWeight(item['id'], newWeight);
                  if (mounted) Navigator.of(context).pop();
                  _refreshData();
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Weight History', style: TextStyle(color: Colors.white)),
        backgroundColor: Theme.of(context).primaryColor,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: const Color(0xFFF5F5F5),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      'Total Entries Logged',
                      style: TextStyle(fontSize: 16, color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_weightData.length}',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(onPressed: () {}, child: const Text('1W')),
                TextButton(onPressed: () {}, child: const Text('1M')),
                TextButton(onPressed: () {}, child: const Text('1Y')),
                TextButton(onPressed: () {}, child: const Text('ALL')),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.only(right: 18.0, top: 24.0, bottom: 12.0),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _weightData.isEmpty
                    ? const Center(child: Text('No weights logged yet. Go to the Log tab!'))
                    : LineChart(
                  LineChartData(
                    minY: _minY,
                    maxY: _maxY,
                    gridData: const FlGridData(show: true, drawVerticalLine: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 22,
                          getTitlesWidget: (value, meta) {
                            if (value % 1 != 0 || value >= _weightData.length) return const Text('');
                            String fullDate = _weightData[value.toInt()]['date'];
                            DateTime parsedDate = DateTime.parse(fullDate);
                            return Text('${parsedDate.day}/${parsedDate.month}', style: const TextStyle(fontSize: 10));
                          },
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    // Enables interactive touch events on the chart nodes
                    lineTouchData: LineTouchData(
                      touchCallback: (FlTouchEvent event, LineTouchResponse? touchResponse) {
                        if (event is FlTapUpEvent && touchResponse != null && touchResponse.lineBarSpots != null) {
                          final int spotIndex = touchResponse.lineBarSpots![0].spotIndex;
                          final Map<String, dynamic> selectedEntry = _weightData[spotIndex];
                          _showEditDialog(selectedEntry);
                        }
                      },
                      handleBuiltInTouches: true,
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: _chartSpots,
                        isCurved: true,
                        color: Theme.of(context).colorScheme.secondary,
                        barWidth: 4,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: true),
                        belowBarData: BarAreaData(
                          show: true,
                          color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// TAB 3: The Settings Screen
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(color: Colors.white)),
        backgroundColor: Theme.of(context).primaryColor,
      ),
      body: ListView(
        children: [
          const ListTile(
            leading: Icon(Icons.person),
            title: Text('Account Profile'),
            subtitle: Text('Not logged in'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.group),
            title: const Text('Team Code'),
            subtitle: const Text('Join or create a team'),
            onTap: () {},
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.login),
            title: const Text('Log In / Sign Up'),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}