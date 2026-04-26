/// Represents a truck/vehicle entry (one truck visit).
class TruckEntry {
  final String id;
  final String vehicleNo; // VEHICLE NO
  final DateTime createdAt; // Arrival timestamp (IN time)
  final DateTime? outTime; // Departure timestamp (OUT time)

  TruckEntry({
    required this.id,
    required this.vehicleNo,
    DateTime? createdAt,
    this.outTime,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Whether the vehicle has left (out time recorded)
  bool get isOut => outTime != null;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'vehicle_no': vehicleNo,
      'created_at': createdAt.toIso8601String(),
      'out_time': outTime?.toIso8601String(),
    };
  }

  factory TruckEntry.fromMap(Map<String, dynamic> map) {
    return TruckEntry(
      id: map['id'] as String,
      vehicleNo: map['vehicle_no'] as String,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : DateTime.now(),
      outTime: map['out_time'] != null
          ? DateTime.parse(map['out_time'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'vehicle_no': vehicleNo,
      'created_at': createdAt.toIso8601String(),
      'out_time': outTime?.toIso8601String(),
    };
  }

  TruckEntry copyWith({
    String? id,
    String? vehicleNo,
    DateTime? createdAt,
    DateTime? outTime,
  }) {
    return TruckEntry(
      id: id ?? this.id,
      vehicleNo: vehicleNo ?? this.vehicleNo,
      createdAt: createdAt ?? this.createdAt,
      outTime: outTime ?? this.outTime,
    );
  }
}
