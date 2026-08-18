// lib/pages/employee_profile_page.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/employee_model.dart';
import '../services/employee_service.dart';

class EmployeeProfilePage extends StatefulWidget {
  final Employee employee;

  const EmployeeProfilePage({Key? key, required this.employee}) : super(key: key);

  @override
  State<EmployeeProfilePage> createState() => _EmployeeProfilePageState();
}

class _EmployeeProfilePageState extends State<EmployeeProfilePage> with SingleTickerProviderStateMixin {
  final EmployeeService _employeeService = EmployeeService();
  List<JobAssignment> _jobs = [];
  List<JobAssignment> _filteredJobs = [];
  bool _isLoading = true;
  String _jobFilter = 'All';
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadEmployeeJobs();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadEmployeeJobs() async {
    setState(() => _isLoading = true);
    try {
      final jobs = await _employeeService.getEmployeeJobs(widget.employee.id);
      setState(() {
        _jobs = jobs;
        _filteredJobs = jobs;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading employee jobs: $e');
      setState(() => _isLoading = false);
    }
  }

  void _filterJobs(String status) {
    setState(() {
      _jobFilter = status;
      if (status == 'All') {
        _filteredJobs = _jobs;
      } else {
        _filteredJobs = _jobs.where((job) => job.status == status).toList();
      }
    });
  }

  Future<void> _updateJobStatus(JobAssignment job, String newStatus) async {
    final success = await _employeeService.updateJobStatus(
      jobId: job.id,
      status: newStatus,
    );

    if (success) {
      _loadEmployeeJobs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Job status updated to ${_getStatusLabel(newStatus)}',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: const Color(0xFF0F172A),
            foregroundColor: Colors.white,
            title: Text(
              widget.employee.name,
              style: GoogleFonts.cairo(fontWeight: FontWeight.w600, color: Colors.white),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF0F172A),
                      Color(0xFF1E293B),
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 35,
                          backgroundColor: Colors.white,
                          child: Text(
                            widget.employee.name[0].toUpperCase(),
                            style: GoogleFonts.cairo(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  _buildSmallBadge(widget.employee.department, Colors.blue),
                                  const SizedBox(width: 8),
                                  _buildSmallBadge(widget.employee.role, Colors.purple),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.employee.email,
                                style: GoogleFonts.cairo(
                                  fontSize: 13,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _buildStatusIndicator(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _SliverAppBarDelegate(
              TabBar(
                controller: _tabController,
                labelColor: const Color(0xFF0F172A),
                unselectedLabelColor: Colors.grey,
                indicatorColor: const Color(0xFF0F172A),
                labelStyle: GoogleFonts.cairo(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                unselectedLabelStyle: GoogleFonts.cairo(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
                tabs: const [
                  Tab(text: 'Information'),
                  Tab(text: 'Assigned Work'),
                ],
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildInformationTab(),
            _buildWorkTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildInformationTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Employee Information',
                    style: GoogleFonts.cairo(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildInfoTile(Icons.email, 'Email', widget.employee.email),
                  _buildInfoTile(Icons.business, 'Department', widget.employee.department),
                  _buildInfoTile(Icons.badge, 'Role', widget.employee.role),
                  if (widget.employee.phoneNumber != null)
                    _buildInfoTile(Icons.phone, 'Phone', widget.employee.phoneNumber!),
                  _buildInfoTile(
                    Icons.calendar_today,
                    'Joined',
                    DateFormat('MMM dd, yyyy').format(widget.employee.createdAt),
                  ),
                  _buildInfoTile(
                    Icons.check_circle,
                    'Status',
                    widget.employee.isActive ? 'Active' : 'Inactive',
                    valueColor: widget.employee.isActive ? Colors.green : Colors.red,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Work Summary
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Work Summary',
                    style: GoogleFonts.cairo(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _buildSummaryCard(
                        'Total Jobs',
                        _jobs.length.toString(),
                        Icons.work,
                        Colors.blue,
                      ),
                      const SizedBox(width: 12),
                      _buildSummaryCard(
                        'In Progress',
                        _jobs.where((j) => j.status == 'in_progress').length.toString(),
                        Icons.timelapse,
                        Colors.orange,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildSummaryCard(
                        'Completed',
                        _jobs.where((j) => j.status == 'completed').length.toString(),
                        Icons.check_circle,
                        Colors.green,
                      ),
                      const SizedBox(width: 12),
                      _buildSummaryCard(
                        'Pending',
                        _jobs.where((j) => j.status == 'pending').length.toString(),
                        Icons.pending,
                        Colors.purple,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('All'),
                _buildFilterChip('pending'),
                _buildFilterChip('in_progress'),
                _buildFilterChip('completed'),
                _buildFilterChip('on_hold'),
              ],
            ),
          ),
        ),
        Expanded(
          child: _filteredJobs.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.work_off, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No jobs assigned',
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          )
              : ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _filteredJobs.length,
            itemBuilder: (context, index) {
              final job = _filteredJobs[index];
              return _buildJobCard(job);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildJobCard(JobAssignment job) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    job.productName,
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStatusColor(job.status).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _getStatusColor(job.status).withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    _getStatusLabel(job.status),
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _getStatusColor(job.status),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.code, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Text(job.productCode, style: GoogleFonts.cairo(fontSize: 13, color: Colors.grey[600])),
                const SizedBox(width: 16),
                const Icon(Icons.engineering, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Text(job.stageName, style: GoogleFonts.cairo(fontSize: 13, color: Colors.grey[600])),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: job.progress / 100,
                      backgroundColor: Colors.grey.withOpacity(0.2),
                      valueColor: AlwaysStoppedAnimation<Color>(_getStatusColor(job.status)),
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${job.progress}%',
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.w600,
                    color: _getStatusColor(job.status),
                  ),
                ),
              ],
            ),
            if (job.dueDate != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 14, color: Colors.red[400]),
                  const SizedBox(width: 4),
                  Text(
                    'Due: ${DateFormat('MMM dd, yyyy').format(job.dueDate!)}',
                    style: GoogleFonts.cairo(fontSize: 12, color: Colors.red[400]),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF64748B)),
          const SizedBox(width: 12),
          Text(label, style: GoogleFonts.cairo(fontSize: 14, color: const Color(0xFF64748B))),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.cairo(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: valueColor ?? const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(value, style: GoogleFonts.cairo(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            Text(title, style: GoogleFonts.cairo(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String status) {
    final isSelected = _jobFilter == status;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: isSelected,
        label: Text(
          _getStatusLabel(status),
          style: GoogleFonts.cairo(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF334155),
          ),
        ),
        onSelected: (selected) => _filterJobs(status),
        selectedColor: const Color(0xFF0F172A),
        checkmarkColor: Colors.white,
        backgroundColor: Colors.white,
        side: BorderSide(
          color: isSelected ? const Color(0xFF0F172A) : Colors.grey.shade300,
        ),
      ),
    );
  }

  Widget _buildSmallBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: GoogleFonts.cairo(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildStatusIndicator() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: widget.employee.isActive ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
        shape: BoxShape.circle,
      ),
      child: Icon(
        widget.employee.isActive ? Icons.check : Icons.close,
        color: widget.employee.isActive ? Colors.green : Colors.red,
        size: 20,
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending': return Colors.orange;
      case 'in_progress': return Colors.blue;
      case 'completed': return Colors.green;
      case 'on_hold': return Colors.red;
      default: return Colors.grey;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'pending': return 'Pending';
      case 'in_progress': return 'In Progress';
      case 'completed': return 'Completed';
      case 'on_hold': return 'On Hold';
      case 'All': return 'All';
      default: return status;
    }
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar _tabBar;

  _SliverAppBarDelegate(this._tabBar);

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(color: Colors.white, child: _tabBar);
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) => false;
}
