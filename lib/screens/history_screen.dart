import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../db/database_helper.dart';
import '../models/scan_record.dart';
import '../providers/scan_provider.dart';
import '../widgets/scan_card.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // Date filter state
  DateTime? _selectedDate; // null = all dates
  List<DateTime> _availableDates = [];
  List<TruckEntry>? _filteredByDate; // null = show all from provider

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<ScanProvider>().loadEntries();
      await _loadAvailableDates();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAvailableDates() async {
    final dates = await DatabaseHelper().getAvailableDates();
    if (mounted) setState(() => _availableDates = dates);
  }

  Future<void> _applyDateFilter(DateTime? date) async {
    setState(() {
      _selectedDate = date;
      _filteredByDate = null;
    });

    if (date == null) return;

    final entries = await DatabaseHelper().getEntriesByDate(date);
    if (mounted) setState(() => _filteredByDate = entries);
  }

  Future<void> _pickFromCalendar() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: DateTime(2020),
      lastDate: now,
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: isDark
                ? ColorScheme.dark(
                    primary: AppTheme.primaryColor,
                    surface: AppTheme.darkCard,
                  )
                : ColorScheme.light(primary: AppTheme.primaryColor),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) await _applyDateFilter(picked);
  }

  String _formatChipDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final day = DateTime(date.year, date.month, date.day);
    if (day == today) return 'Today';
    if (day == yesterday) return 'Yesterday';
    return '${date.day}/${date.month}/${date.year}';
  }

  List<TruckEntry> _getDisplayEntries(ScanProvider provider) {
    if (_selectedDate != null) {
      return _filteredByDate ?? [];
    }
    return provider.entries;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: CustomScrollView(
          slivers: [
            // ─── Gradient Header ────────────────────────
            SliverAppBar(
              expandedHeight: 120,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
                title: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Vehicle History',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Consumer<ScanProvider>(
                      builder: (context, provider, _) {
                        final count = _selectedDate != null
                            ? (_filteredByDate?.length ?? 0)
                            : provider.totalCount;
                        final label = _selectedDate != null
                            ? '$count on ${_formatChipDate(_selectedDate!)}'
                            : '$count entries';
                        return Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                            color: isDark
                                ? AppTheme.darkTextMuted
                                : AppTheme.lightTextMuted,
                          ),
                        );
                      },
                    ),
                  ],
                ),
                background: Container(
                  decoration: BoxDecoration(
                    gradient: isDark
                        ? AppTheme.darkHeaderGradient
                        : LinearGradient(
                            colors: [
                              AppTheme.primaryColor.withValues(alpha: 0.08),
                              AppTheme.lightBg,
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                  ),
                ),
              ),
            ),

            // ─── Search Bar ──────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: isDark
                            ? Colors.black.withValues(alpha: 0.15)
                            : Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by vehicle number...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                context.read<ScanProvider>().searchEntries('');
                                setState(() {});
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      filled: true,
                      fillColor: isDark ? AppTheme.darkCard : Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: isDark
                              ? AppTheme.darkBorder
                              : AppTheme.lightBorder,
                          width: 0.5,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: AppTheme.primaryColor,
                          width: 1.5,
                        ),
                      ),
                    ),
                    onChanged: (query) {
                      context.read<ScanProvider>().searchEntries(query);
                      setState(() {});
                    },
                  ),
                ),
              ),
            ),

            // ─── Date Filter Strip ───────────────────────
            SliverToBoxAdapter(
              child: _availableDates.isEmpty
                  ? const SizedBox(height: 8)
                  : Padding(
                      padding: const EdgeInsets.only(
                        left: 16,
                        top: 4,
                        bottom: 4,
                      ),
                      child: SizedBox(
                        height: 38,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            // "All" chip
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: const Text('All'),
                                selected: _selectedDate == null,
                                showCheckmark: false,
                                selectedColor: AppTheme.primaryColor.withValues(
                                  alpha: 0.18,
                                ),
                                labelStyle: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                  color: _selectedDate == null
                                      ? AppTheme.primaryColor
                                      : (isDark
                                            ? AppTheme.darkTextMuted
                                            : AppTheme.lightTextMuted),
                                ),
                                side: BorderSide(
                                  color: _selectedDate == null
                                      ? AppTheme.primaryColor
                                      : (isDark
                                            ? AppTheme.darkBorder
                                            : AppTheme.lightBorder),
                                ),
                                onSelected: (_) => _applyDateFilter(null),
                              ),
                            ),
                            // Per-day chips
                            ..._availableDates.take(7).map((date) {
                              final isSelected =
                                  _selectedDate != null &&
                                  DateTime(
                                        _selectedDate!.year,
                                        _selectedDate!.month,
                                        _selectedDate!.day,
                                      ) ==
                                      DateTime(date.year, date.month, date.day);
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: FilterChip(
                                  label: Text(_formatChipDate(date)),
                                  selected: isSelected,
                                  showCheckmark: false,
                                  selectedColor: AppTheme.primaryColor
                                      .withValues(alpha: 0.18),
                                  labelStyle: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    color: isSelected
                                        ? AppTheme.primaryColor
                                        : (isDark
                                              ? AppTheme.darkTextMuted
                                              : AppTheme.lightTextMuted),
                                  ),
                                  side: BorderSide(
                                    color: isSelected
                                        ? AppTheme.primaryColor
                                        : (isDark
                                              ? AppTheme.darkBorder
                                              : AppTheme.lightBorder),
                                  ),
                                  onSelected: (_) => _applyDateFilter(date),
                                ),
                              );
                            }),
                            // Calendar picker chip
                            Padding(
                              padding: const EdgeInsets.only(right: 16),
                              child: ActionChip(
                                avatar: const Icon(
                                  Icons.calendar_month_rounded,
                                  size: 15,
                                ),
                                label: const Text('Pick Date'),
                                labelStyle: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                side: BorderSide(
                                  color: isDark
                                      ? AppTheme.darkBorder
                                      : AppTheme.lightBorder,
                                ),
                                onPressed: _pickFromCalendar,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),

            // ─── Entry List ──────────────────────────────
            Consumer<ScanProvider>(
              builder: (context, provider, _) {
                if (provider.isLoading) {
                  return const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final entries = _getDisplayEntries(provider);

                if (entries.isEmpty) {
                  return SliverFillRemaining(child: _buildEmptyState(isDark));
                }

                return SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    if (index == entries.length) {
                      return const SizedBox(height: 100);
                    }
                    return ScanCard(entry: entries[index]);
                  }, childCount: entries.length + 1),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryColor.withValues(alpha: 0.12),
                  AppTheme.accentColor.withValues(alpha: 0.06),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(
              _selectedDate != null
                  ? Icons.event_busy_rounded
                  : _searchController.text.isNotEmpty
                  ? Icons.search_off_rounded
                  : Icons.local_shipping_rounded,
              size: 40,
              color: AppTheme.primaryColor.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _selectedDate != null
                ? 'No arrivals on ${_formatChipDate(_selectedDate!)}'
                : _searchController.text.isNotEmpty
                ? 'No results found'
                : 'No entries yet',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            _selectedDate != null
                ? 'Try another date or tap All'
                : _searchController.text.isNotEmpty
                ? 'Try a different search term'
                : 'Capture a vehicle to get started',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_selectedDate != null) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => _applyDateFilter(null),
              icon: const Icon(Icons.clear_rounded, size: 16),
              label: const Text('Clear filter'),
            ),
          ],
        ],
      ),
    );
  }
}
