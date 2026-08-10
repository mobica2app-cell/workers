// lib/widgets/job_assignment_dialog.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/employee_model.dart';
import '../services/employee_service.dart';

class JobAssignmentDialog extends StatefulWidget {
  final String productCode;
  final String productName;
  final String currentStage;

  const JobAssignmentDialog({
    Key? key,
    required this.productCode,
    required this.productName,
    required this.currentStage,
  }) : super(key: key);

  @override
  State<JobAssignmentDialog> createState() => _JobAssignmentDialogState();
}

class _JobAssignmentDialogState extends State<JobAssignmentDialog> {
  final EmployeeService _employeeService = EmployeeService();
  List<Employee> _employees = [];
  Employee? _selectedEmployee;
  DateTime? _dueDate;
  final TextEditingController _notesController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    final employees = await _employeeService.getEmployees(isActive: true);
    setState(() {
      _employees = employees;
    });
  }

  Future<void> _assignJob() async {
    if (_selectedEmployee == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please select an employee',
            style: GoogleFonts.cairo(),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final success = await _employeeService.assignJob(
      productCode: widget.productCode,
      productName: widget.productName,
      employeeId: _selectedEmployee!.id,
      employeeName: _selectedEmployee!.name,
      stageName: widget.currentStage,
      dueDate: _dueDate,
      notes: _notesController.text.isEmpty ? null : _notesController.text,
    );

    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Job assigned successfully',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to assign job',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Assign Job',
        style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Product', widget.productName),
            _buildInfoRow('Stage', widget.currentStage),
            const SizedBox(height: 16),
            Text(
              'Assign to Employee:',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<Employee>(
              value: _selectedEmployee,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: 'Select employee',
                hintStyle: GoogleFonts.cairo(),
              ),
              items: _employees.map((employee) {
                return DropdownMenuItem(
                  value: employee,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employee.name,
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${employee.department} - ${employee.role}',
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => _selectedEmployee = value);
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Due Date:',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now().add(const Duration(days: 7)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (date != null) {
                  setState(() => _dueDate = date);
                }
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today),
                    const SizedBox(width: 8),
                    Text(
                      _dueDate != null
                          ? DateFormat('MMM dd, yyyy').format(_dueDate!)
                          : 'Select due date',
                      style: GoogleFonts.cairo(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Notes',
                labelStyle: GoogleFonts.cairo(),
                border: const OutlineInputBorder(),
                hintText: 'Add any notes or instructions...',
                hintStyle: GoogleFonts.cairo(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: GoogleFonts.cairo()),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _assignJob,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6366F1),
          ),
          child: _isLoading
              ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : Text(
            'Assign Job',
            style: GoogleFonts.cairo(color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: GoogleFonts.cairo(
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          Text(
            value,
            style: GoogleFonts.cairo(),
          ),
        ],
      ),
    );
  }
}