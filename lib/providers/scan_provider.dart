import 'package:flutter/material.dart';
import '../models/scan_record.dart';
import '../db/database_helper.dart';
import '../api/sync_service.dart';

class ScanProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper();
  final SyncService _syncService = SyncService();

  List<TruckEntry> _entries = [];
  List<TruckEntry> _filteredEntries = [];
  bool _isLoading = false;
  String _searchQuery = '';

  List<TruckEntry> get entries =>
      _searchQuery.isEmpty ? _entries : _filteredEntries;
  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;
  int get totalCount => _entries.length;

  /// Load all truck entries from the database
  Future<void> loadEntries() async {
    _isLoading = true;
    notifyListeners();

    try {
      _entries = await _db.getAllEntries();
      if (_searchQuery.isNotEmpty) {
        _filteredEntries = await _db.searchByVehicleNo(_searchQuery);
      }
    } catch (e) {
      debugPrint('Error loading entries: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Send a vehicle scan to the server and handle the response locally.
  /// Returns the ScanResponse so the UI can show the appropriate message.
  Future<ScanResponse> scanVehicle(String vehicleNo) async {
    final response = await _syncService.scanVehicle(vehicleNo);

    if (response.success) {
      if (response.action == 'ARRIVAL') {
        // Create a local entry for history
        final entry = TruckEntry(
          id: '${vehicleNo}_${DateTime.now().millisecondsSinceEpoch}',
          vehicleNo: vehicleNo,
        );
        await _db.insertEntry(entry);
        _entries.insert(0, entry);
        notifyListeners();
      } else if (response.action == 'DEPARTURE') {
        // Find the active entry and mark it out
        final activeEntry = await _db.findActiveEntry(vehicleNo);
        if (activeEntry != null) {
          await _db.updateOutTime(activeEntry.id, DateTime.now());
        } else {
          // If this phone didn't scan the arrival natively (e.g. data cleared),
          // we still want to log the departure in the history screen!
          final entry = TruckEntry(
            id: '${vehicleNo}_${DateTime.now().millisecondsSinceEpoch}',
            vehicleNo: vehicleNo,
            outTime: DateTime.now(),
          );
          await _db.insertEntry(entry);
        }
        await loadEntries();
      }
    }

    return response;
  }

  /// Add a new truck entry (local-only, for manual entry)
  Future<void> addEntry(TruckEntry entry) async {
    try {
      await _db.insertEntry(entry);
      _entries.insert(0, entry);
      notifyListeners();

      // Sync to dashboard in background
      _syncService.scanVehicle(entry.vehicleNo).then((response) {
        if (response.success) {
          debugPrint('${response.action} for ${entry.vehicleNo} synced');
        }
      });
    } catch (e) {
      debugPrint('Error adding entry: $e');
      rethrow;
    }
  }

  /// Delete a truck entry
  Future<void> deleteEntry(String id) async {
    try {
      await _db.deleteEntry(id);
      _entries.removeWhere((e) => e.id == id);
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting entry: $e');
      rethrow;
    }
  }

  /// Search entries by truck number
  Future<void> searchEntries(String query) async {
    _searchQuery = query;
    if (query.isEmpty) {
      _filteredEntries = [];
    } else {
      _filteredEntries = await _db.searchByVehicleNo(query);
    }
    notifyListeners();
  }

  /// Sync all pending entries
  Future<SyncResult> syncAll() async {
    _isLoading = true;
    notifyListeners();

    final result = await _syncService.syncAllPending();

    // Reload to update sync statuses
    await loadEntries();

    return result;
  }

  /// Get a single entry by ID
  Future<TruckEntry?> getEntryById(String id) async {
    return await _db.getEntryById(id);
  }

  /// Find an active entry (in but not out) for a vehicle number
  Future<TruckEntry?> findActiveEntry(String vehicleNo) async {
    return await _db.findActiveEntry(vehicleNo);
  }

  /// Mark an entry as OUT (vehicle leaving) — for manual mark out
  Future<void> markOut(String id) async {
    try {
      final entry = await _db.getEntryById(id);
      await _db.updateOutTime(id, DateTime.now());
      await loadEntries();

      // Sync to dashboard in background
      if (entry != null) {
        _syncService.scanVehicle(entry.vehicleNo).then((response) {
          if (response.success) {
            debugPrint('${response.action} for ${entry.vehicleNo} synced');
          }
        });
      }
    } catch (e) {
      debugPrint('Error marking out: $e');
      rethrow;
    }
  }

  /// Clear all local data
  Future<void> clearAll() async {
    await _db.clearAll();
    _entries.clear();
    _filteredEntries.clear();
    _searchQuery = '';
    notifyListeners();
  }
}
