import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/serfix_provider.dart';

class SerfixMainScreen extends StatefulWidget {
  const SerfixMainScreen({super.key});

  @override
  State<SerfixMainScreen> createState() => _SerfixMainScreenState();
}

class _SerfixMainScreenState extends State<SerfixMainScreen> {
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final serfix = context.watch<SerfixProvider>();
    final user = context.watch<AuthProvider>().currentUser;
    final role = serfix.role;
    final title = switch (_selectedTab) {
      1 => 'Daftar layanan',
      2 => 'Akun',
      _ => 'SerFix',
    };

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.home_repair_service_rounded,
                color: Color(0xFF0F8B80)),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        actions: [
          PopupMenuButton<SerfixRole>(
            tooltip: 'Ganti peran demo',
            initialValue: role,
            onSelected: serfix.setRole,
            itemBuilder: (context) => SerfixRole.values
                .map((item) => PopupMenuItem(
                      value: item,
                      child: Row(
                        children: [
                          Icon(_roleIcon(item), size: 19),
                          const SizedBox(width: 10),
                          Text(item.label),
                        ],
                      ),
                    ))
                .toList(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Chip(
                avatar: Icon(_roleIcon(role), size: 16),
                label: Text(role.label),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedTab,
        children: [
          _Dashboard(user: user),
          const _RequestList(),
          _AccountPage(user: user, role: role),
        ],
      ),
      floatingActionButton: role == SerfixRole.customer && _selectedTab != 2
          ? FloatingActionButton.extended(
              onPressed: () => _openRequestForm(context),
              icon: const Icon(Icons.add),
              label: const Text('Ajukan servis'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) => setState(() => _selectedTab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.space_dashboard_outlined),
            selectedIcon: Icon(Icons.space_dashboard),
            label: 'Beranda',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment),
            label: 'Layanan',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Akun',
          ),
        ],
      ),
    );
  }

  Future<void> _openRequestForm(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _RequestFormSheet(),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.user});

  final User? user;

  @override
  Widget build(BuildContext context) {
    final serfix = context.watch<SerfixProvider>();
    final requests = serfix.requests;
    final role = serfix.role;
    final name = user?.name ?? 'Pelanggan';
    final customerRequests =
        requests.where((request) => request.customerName == name).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 100),
      children: [
        Text(
          role == SerfixRole.customer
              ? 'Halo, $name 👋'
              : 'Halo, ${role.label} 👋',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        Text(_dashboardSubtitle(role),
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 18),
        _DemoNotice(role: role),
        const SizedBox(height: 16),
        if (role == SerfixRole.customer) ...[
          _CustomerDashboard(requests: customerRequests),
        ] else if (role == SerfixRole.technician) ...[
          _TechnicianDashboard(requests: serfix.technicianRequests),
        ] else if (role == SerfixRole.admin) ...[
          _AdminDashboard(requests: requests, provider: serfix),
        ] else ...[
          _ManagerDashboard(requests: requests),
        ],
      ],
    );
  }
}

class _CustomerDashboard extends StatelessWidget {
  const _CustomerDashboard({required this.requests});

  final List<SerfixRequest> requests;

  @override
  Widget build(BuildContext context) {
    final active = requests
        .where((request) => request.status != ServiceRequestStatus.completed)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeroCard(
          title: 'Servis rumah, tanpa ribet.',
          subtitle: 'Pesan teknisi tepercaya dan pantau prosesnya dari rumah.',
          icon: Icons.ac_unit_rounded,
          buttonLabel: 'Buat pengajuan servis',
          onPressed: () => _showRequestForm(context),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
                child: _MetricCard(
                    label: 'Servis aktif',
                    value: '$active',
                    icon: Icons.handyman_outlined)),
            const SizedBox(width: 10),
            const Expanded(
                child: _MetricCard(
                    label: 'Garansi aktif',
                    value: '1',
                    icon: Icons.verified_outlined)),
          ],
        ),
        const SizedBox(height: 22),
        const _SectionHeading(title: 'Servis terbaru'),
        const SizedBox(height: 10),
        if (requests.isEmpty)
          const _InfoTile(
            icon: Icons.inbox_outlined,
            title: 'Belum ada riwayat servis',
            subtitle: 'Pengajuan servis yang dibuat akan muncul di sini.',
          ),
        ...requests.take(2).map((request) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RequestCard(request: request),
            )),
      ],
    );
  }
}

class _TechnicianDashboard extends StatelessWidget {
  const _TechnicianDashboard({required this.requests});

  final List<SerfixRequest> requests;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeading(title: 'Ringkasan kerja hari ini'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
                child: _MetricCard(
                    label: 'Work order',
                    value: '${requests.length}',
                    icon: Icons.assignment_turned_in_outlined)),
            const SizedBox(width: 10),
            const Expanded(
                child: _MetricCard(
                    label: 'Perlu ditangani',
                    value: '1',
                    icon: Icons.pending_actions)),
          ],
        ),
        const SizedBox(height: 22),
        const _SectionHeading(title: 'Penugasan teknisi'),
        const SizedBox(height: 10),
        ...requests.map((request) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RequestCard(request: request, showCustomer: true),
            )),
        const _InfoTile(
          icon: Icons.fact_check_outlined,
          title: 'Work order terstruktur',
          subtitle:
              'Catat diagnosis, pekerjaan, sparepart, dan foto hasil servis.',
        ),
      ],
    );
  }
}

class _AdminDashboard extends StatelessWidget {
  const _AdminDashboard({required this.requests, required this.provider});

  final List<SerfixRequest> requests;
  final SerfixProvider provider;

  @override
  Widget build(BuildContext context) {
    final conflicts = requests
        .where((request) => provider.hasTechnicianConflict(request))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
                child: _MetricCard(
                    label: 'Pengajuan',
                    value: '${requests.length}',
                    icon: Icons.inbox_outlined)),
            const SizedBox(width: 10),
            const Expanded(
                child: _MetricCard(
                    label: 'Teknisi aktif',
                    value: '4',
                    icon: Icons.engineering_outlined)),
          ],
        ),
        const SizedBox(height: 20),
        if (conflicts.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFFCC80)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFB76500)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${conflicts.length} jadwal bentrok terdeteksi untuk ${conflicts.first.technicianName}. Atur ulang penugasan sebelum konfirmasi.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 20),
        const _SectionHeading(title: 'Jadwal dan penugasan'),
        const SizedBox(height: 10),
        ...requests.map((request) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RequestCard(
                request: request,
                showCustomer: true,
                conflict: provider.hasTechnicianConflict(request),
              ),
            )),
        const _InfoTile(
          icon: Icons.inventory_2_outlined,
          title: 'Stok sparepart',
          subtitle: 'Kelola penggunaan dan ketersediaan komponen servis.',
        ),
      ],
    );
  }
}

class _ManagerDashboard extends StatelessWidget {
  const _ManagerDashboard({required this.requests});

  final List<SerfixRequest> requests;

  @override
  Widget build(BuildContext context) {
    final completed = requests
        .where((request) => request.status == ServiceRequestStatus.completed)
        .length;
    final total =
        requests.fold<int>(0, (sum, request) => sum + request.estimate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeading(title: 'Ringkasan operasional'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
                child: _MetricCard(
                    label: 'Total layanan',
                    value: '${requests.length}',
                    icon: Icons.home_repair_service_outlined)),
            const SizedBox(width: 10),
            Expanded(
                child: _MetricCard(
                    label: 'Selesai',
                    value: '$completed',
                    icon: Icons.task_alt)),
          ],
        ),
        const SizedBox(height: 10),
        _MetricCard(
            label: 'Nilai estimasi servis',
            value: _formatRupiah(total),
            icon: Icons.payments_outlined),
        const SizedBox(height: 22),
        const _SectionHeading(title: 'Transparansi dan garansi'),
        const SizedBox(height: 10),
        const _InfoTile(
          icon: Icons.receipt_long_outlined,
          title: 'Estimasi sebelum pengerjaan',
          subtitle:
              'Pelanggan menyetujui perubahan biaya sebelum work order dilanjutkan.',
        ),
        const SizedBox(height: 10),
        const _InfoTile(
          icon: Icons.verified_user_outlined,
          title: 'Riwayat dan garansi servis',
          subtitle:
              'Pekerjaan, sparepart, pembayaran, dan masa garansi tercatat per pengajuan.',
        ),
      ],
    );
  }
}

class _RequestList extends StatelessWidget {
  const _RequestList();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SerfixProvider>();
    final role = provider.role;
    final userName = context.watch<AuthProvider>().currentUser?.name;
    final requests = role == SerfixRole.technician
        ? provider.technicianRequests
        : role == SerfixRole.customer
            ? provider.requests
                .where((request) => request.customerName == userName)
                .toList()
            : provider.requests;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      children: [
        Text('Pengajuan dan work order',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text('Status, jadwal, estimasi, dan detail servis.'),
        const SizedBox(height: 16),
        if (requests.isEmpty)
          const _InfoTile(
            icon: Icons.inbox_outlined,
            title: 'Belum ada pengajuan',
            subtitle: 'Ajukan layanan servis untuk mulai memantau progresnya.',
          )
        else
          ...requests.map((request) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _RequestCard(
                  request: request,
                  showCustomer: role != SerfixRole.customer,
                  conflict: role == SerfixRole.admin &&
                      provider.hasTechnicianConflict(request),
                ),
              )),
      ],
    );
  }
}

class _AccountPage extends StatelessWidget {
  const _AccountPage({required this.user, required this.role});

  final User? user;
  final SerfixRole role;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        CircleAvatar(
          radius: 34,
          backgroundColor: const Color(0xFFE0F2F1),
          child:
              Icon(_roleIcon(role), size: 34, color: const Color(0xFF0F8B80)),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(user?.name ?? 'Pengguna SerFix',
              style: Theme.of(context).textTheme.titleLarge),
        ),
        Center(child: Text(user?.email ?? '')),
        const SizedBox(height: 20),
        _InfoTile(
          icon: Icons.badge_outlined,
          title: 'Peran aktif',
          subtitle: '${role.label} · mode demonstrasi',
        ),
        const SizedBox(height: 10),
        const _InfoTile(
          icon: Icons.support_agent,
          title: 'Bantuan SerFix',
          subtitle:
              'Jadwal, estimasi biaya, pembayaran, riwayat, dan garansi servis.',
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: () => context.read<AuthProvider>().logout(),
          icon: const Icon(Icons.logout),
          label: const Text('Keluar'),
        ),
      ],
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    this.showCustomer = false,
    this.conflict = false,
  });

  final SerfixRequest request;
  final bool showCustomer;
  final bool conflict;

  @override
  Widget build(BuildContext context) {
    final date = _formatDateTime(request.scheduledAt);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFFE0F2F1),
                  child: Icon(_serviceIcon(request.service),
                      color: const Color(0xFF0F8B80)),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(request.service,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(request.device,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                _StatusBadge(status: request.status),
              ],
            ),
            const Divider(height: 22),
            _DetailRow(icon: Icons.schedule, text: date),
            const SizedBox(height: 7),
            _DetailRow(
              icon: Icons.person_outline,
              text: showCustomer
                  ? 'Pelanggan: ${request.customerName}'
                  : 'Teknisi: ${request.technicianName ?? 'Menunggu penugasan'}',
            ),
            const SizedBox(height: 7),
            _DetailRow(icon: Icons.location_on_outlined, text: request.address),
            const SizedBox(height: 11),
            Row(
              children: [
                const Icon(Icons.receipt_long_outlined, size: 17),
                const SizedBox(width: 6),
                Text('Estimasi ${_formatRupiah(request.estimate)}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            if (request.parts.isNotEmpty || request.warrantyMonths > 0) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  ...request.parts.map((part) => _MiniTag(
                        icon: Icons.build_outlined,
                        text: part,
                      )),
                  if (request.warrantyMonths > 0)
                    _MiniTag(
                      icon: Icons.verified_outlined,
                      text: 'Garansi ${request.warrantyMonths} bulan',
                    ),
                ],
              ),
            ],
            if (conflict) ...[
              const SizedBox(height: 10),
              const _MiniTag(
                icon: Icons.warning_amber_rounded,
                text: 'Jadwal teknisi bentrok',
                warning: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RequestFormSheet extends StatefulWidget {
  const _RequestFormSheet();

  @override
  State<_RequestFormSheet> createState() => _RequestFormSheetState();
}

class _RequestFormSheetState extends State<_RequestFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _deviceController = TextEditingController();
  final _addressController = TextEditingController();
  String _service = 'Servis AC';
  late DateTime _selectedSlot;
  late final DateTime _serviceDay;
  static const _hours = [9, 11, 13, 15];

  @override
  void initState() {
    super.initState();
    _serviceDay = DateTime.now().add(const Duration(days: 1));
    _selectedSlot =
        DateTime(_serviceDay.year, _serviceDay.month, _serviceDay.day, 13);
  }

  @override
  void dispose() {
    _deviceController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final serfix = context.watch<SerfixProvider>();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text('Ajukan layanan servis',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _service,
                decoration: const InputDecoration(labelText: 'Jenis layanan'),
                items: const [
                  DropdownMenuItem(
                      value: 'Servis AC', child: Text('Servis AC')),
                  DropdownMenuItem(
                      value: 'Perbaikan kulkas',
                      child: Text('Perbaikan kulkas')),
                  DropdownMenuItem(
                      value: 'Servis mesin cuci',
                      child: Text('Servis mesin cuci')),
                  DropdownMenuItem(
                      value: 'Perbaikan elektronik',
                      child: Text('Perbaikan elektronik')),
                ],
                onChanged: (value) => setState(() => _service = value!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _deviceController,
                decoration: const InputDecoration(
                  labelText: 'Perangkat dan keluhan',
                  hintText: 'Contoh: AC 1 PK tidak dingin',
                ),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Alamat servis',
                  hintText: 'Alamat lengkap dan area',
                ),
                validator: _required,
              ),
              const SizedBox(height: 16),
              Text(
                'Pilih jadwal · ${_formatDate(_serviceDay)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _hours.map((hour) {
                  final slot = DateTime(_serviceDay.year, _serviceDay.month,
                      _serviceDay.day, hour);
                  final available = serfix.isSlotAvailable(slot);
                  return ChoiceChip(
                    label: Text('${hour.toString().padLeft(2, '0')}.00'
                        '${available ? '' : ' · penuh'}'),
                    selected: _selectedSlot == slot,
                    onSelected: available
                        ? (_) => setState(() => _selectedSlot = slot)
                        : null,
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const _InfoTile(
                icon: Icons.price_check_outlined,
                title: 'Estimasi awal ditampilkan sebelum konfirmasi',
                subtitle:
                    'Biaya akhir mengikuti diagnosis dan persetujuan pelanggan.',
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    if (!_formKey.currentState!.validate()) return;
                    try {
                      context.read<SerfixProvider>().createRequest(
                            customerName: context
                                    .read<AuthProvider>()
                                    .currentUser
                                    ?.name ??
                                'Pelanggan',
                            service: _service,
                            device: _deviceController.text.trim(),
                            address: _addressController.text.trim(),
                            scheduledAt: _selectedSlot,
                          );
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Pengajuan servis berhasil dibuat.')),
                      );
                    } on StateError catch (error) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(error.message)),
                      );
                    }
                  },
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Kirim pengajuan'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Wajib diisi' : null;
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F8B80), Color(0xFF075C58)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 30, color: Colors.white),
          const SizedBox(height: 14),
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 15),
          FilledButton.tonal(
            onPressed: onPressed,
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(
      {required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFF0F8B80)),
            const SizedBox(height: 10),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) =>
      Text(title, style: Theme.of(context).textTheme.titleMedium);
}

class _DemoNotice extends StatelessWidget {
  const _DemoNotice({required this.role});

  final SerfixRole role;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4FF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 19, color: Color(0xFF2C64A0)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Tampilan demonstrasi · peran ${role.label}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF23496E)),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF0F8B80)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: const Color(0xFF72808C)),
          const SizedBox(width: 7),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        ],
      );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final ServiceRequestStatus status;

  @override
  Widget build(BuildContext context) {
    final Color color;
    switch (status) {
      case ServiceRequestStatus.requested:
      case ServiceRequestStatus.waitingApproval:
        color = const Color(0xFFB76500);
      case ServiceRequestStatus.scheduled:
        color = const Color(0xFF2868A8);
      case ServiceRequestStatus.inProgress:
        color = const Color(0xFF0F8B80);
      case ServiceRequestStatus.completed:
        color = const Color(0xFF23865F);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(status.label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({
    required this.icon,
    required this.text,
    this.warning = false,
  });

  final IconData icon;
  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final color = warning ? const Color(0xFFB76500) : const Color(0xFF0F716A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}

Future<void> _showRequestForm(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _RequestFormSheet(),
  );
}

IconData _roleIcon(SerfixRole role) => switch (role) {
      SerfixRole.customer => Icons.person_outline,
      SerfixRole.technician => Icons.engineering_outlined,
      SerfixRole.admin => Icons.manage_accounts_outlined,
      SerfixRole.manager => Icons.analytics_outlined,
    };

IconData _serviceIcon(String service) => service.toLowerCase().contains('ac')
    ? Icons.ac_unit
    : Icons.home_repair_service;

String _dashboardSubtitle(SerfixRole role) => switch (role) {
      SerfixRole.customer => 'Pantau layanan rumah dalam satu aplikasi.',
      SerfixRole.technician => 'Lihat tugas, jadwal, dan detail work order.',
      SerfixRole.admin => 'Kelola penugasan, jadwal, dan penggunaan sparepart.',
      SerfixRole.manager => 'Pantau operasional dan transparansi layanan.',
    };

String _formatRupiah(int amount) {
  final digits = amount.toString();
  final grouped = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) grouped.write('.');
    grouped.write(digits[index]);
  }
  return 'Rp $grouped';
}

String _formatDate(DateTime date) => '${date.day} ${_months[date.month - 1]}';

String _formatDateTime(DateTime date) {
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '${_weekdays[date.weekday - 1]}, ${_formatDate(date)} · $hour.$minute';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'Mei',
  'Jun',
  'Jul',
  'Agu',
  'Sep',
  'Okt',
  'Nov',
  'Des',
];

const _weekdays = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
