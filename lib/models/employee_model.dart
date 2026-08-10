// lib/models/employee_model.dart
class Employee {
  final String id;
  final String email;
  final String name;
  final String department;
  final String role;
  final String? phoneNumber;
  final String? profileImageUrl;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? updatedAt;
  Employee({
    required this.id,
    required this.email,
    required this.name,
    required this.department,
    required this.role,
    this.phoneNumber,
    this.profileImageUrl,
    required this.isActive,
    required this.createdAt,
    this.updatedAt,
  });

  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      name: json['name'] ?? '',
      department: json['department'] ?? '',
      role: json['role'] ?? '',
      phoneNumber: json['phone_number'],
      profileImageUrl: json['profile_image_url'],
      isActive: json['is_active'] ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'department': department,
      'role': role,
      'phone_number': phoneNumber,
      'profile_image_url': profileImageUrl,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  // Role types
  static const List<String> availableRoles = [
    'Admin',
    'Manager',
    'Designer',
    'Production Manager',
    'Quality Control',
    'Worker',
    'Viewer',
  ];

  // Department types
  static const List<String> availableDepartments = [
    'Management',
    'Design',
    'Production',
    'Quality Control',
    'Sales',
  ];
}

class JobAssignment {
  final String id;
  final String productCode;
  final String productName;
  final String employeeId;
  final String employeeName;
  final String stageName;
  final String status;
  final DateTime? assignedDate;
  final DateTime? dueDate;
  final DateTime? completedDate;
  final String? notes;
  final int progress;

  JobAssignment({
    required this.id,
    required this.productCode,
    required this.productName,
    required this.employeeId,
    required this.employeeName,
    required this.stageName,
    required this.status,
    this.assignedDate,
    this.dueDate,
    this.completedDate,
    this.notes,
    required this.progress,
  });

  factory JobAssignment.fromJson(Map<String, dynamic> json) {
    return JobAssignment(
      id: json['id'] ?? '',
      productCode: json['product_code'] ?? '',
      productName: json['product_name'] ?? '',
      employeeId: json['employee_id'] ?? '',
      employeeName: json['employee_name'] ?? '',
      stageName: json['stage_name'] ?? '',
      status: json['status'] ?? 'pending',
      assignedDate: json['assigned_date'] != null
          ? DateTime.parse(json['assigned_date'])
          : null,
      dueDate: json['due_date'] != null
          ? DateTime.parse(json['due_date'])
          : null,
      completedDate: json['completed_date'] != null
          ? DateTime.parse(json['completed_date'])
          : null,
      notes: json['notes'],
      progress: json['progress'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_code': productCode,
      'product_name': productName,
      'employee_id': employeeId,
      'employee_name': employeeName,
      'stage_name': stageName,
      'status': status,
      'assigned_date': assignedDate?.toIso8601String(),
      'due_date': dueDate?.toIso8601String(),
      'completed_date': completedDate?.toIso8601String(),
      'notes': notes,
      'progress': progress,
    };
  }
}