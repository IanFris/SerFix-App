import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/serfix_provider.dart';
import '../settings/settings_screen.dart';

class SerfixMainScreen extends StatefulWidget {
  const SerfixMainScreen({super.key});

  @override
  State<SerfixMainScreen> createState() => _SerfixMainScreenState();
}

class _SerfixMainScreenState extends State<SerfixMainScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AuthProvider>().currentUser;
      if (user != null) context.read<SerfixProvider>().load(user);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SerfixProvider>();
    final user = context.watch<AuthProvider>().currentUser;
    final role = provider.role;
    final labels = ['Beranda', 'Layanan', 'Pesan', 'Garansi', 'Akun'];
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.home_repair_service_rounded,
                color: Color(0xFF0F8B80)),
            const SizedBox(width: 8),
            Text('SerFix · ${labels[_tab]}'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Notifikasi',
            onPressed: () => _openNotifications(context),
            icon: Badge(
              isLabelVisible: provider.notifications
                  .any((item) => item['is_read'] == 0 || item['is_read'] == false),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Chip(
              avatar: Icon(_roleIcon(role), size: 16),
              label: Text(role.label),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (provider.errorMessage != null)
            MaterialBanner(
              content: Text(provider.errorMessage!),
              leading: const Icon(Icons.cloud_off_outlined),
              actions: [
                TextButton(
                  onPressed: provider.isLoading ? null : provider.refresh,
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          if (provider.isLoading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                _Dashboard(
                    user: user,
                    onNavigate: (tab) => setState(() => _tab = tab)),
                const _RequestList(),
                const _MessageList(),
                const _WarrantyList(),
                _AccountPage(user: user),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: role == SerfixRole.customer && (_tab == 0 || _tab == 1)
          ? FloatingActionButton.extended(
              onPressed: () => _openRequestForm(context),
              icon: const Icon(Icons.add),
              label: const Text('Ajukan servis'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
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
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Pesan',
          ),
          NavigationDestination(
            icon: Icon(Icons.verified_user_outlined),
            selectedIcon: Icon(Icons.verified_user),
            label: 'Garansi',
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

  Future<void> _openNotifications(BuildContext context) async {
    final provider = context.read<SerfixProvider>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('Notifikasi',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                    ),
                    TextButton(
                      onPressed: () async {
                        await provider.readNotifications();
                        setSheetState(() {});
                      },
                      child: const Text('Tandai dibaca'),
                    ),
                  ],
                ),
                if (provider.notifications.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('Belum ada notifikasi.')),
                  )
                else
                  ...provider.notifications.take(20).map((item) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          item['is_read'] == 1
                              ? Icons.notifications_none
                              : Icons.notifications_active_outlined,
                          color: const Color(0xFF0F8B80),
                        ),
                        title: Text(item['title']?.toString() ?? ''),
                        subtitle: Text(item['message']?.toString() ?? ''),
                      )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.user, required this.onNavigate});

  final User? user;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SerfixProvider>();
    final role = provider.role;
    final summary = provider.summary;
    final requests = provider.requests;
    final name = user?.name ?? '';
    final personalRequests = role == SerfixRole.customer
        ? requests.where((request) => request.customerId == user?.id).toList()
        : requests;

    return RefreshIndicator(
      onRefresh: provider.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 96),
        children: [
          Text(
            role == SerfixRole.customer
                ? 'Halo, $name 👋'
                : 'Halo, ${role.label} 👋',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(_subtitle(role), style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 18),
          if (role == SerfixRole.customer)
            _HeroCard(
              title: 'Servis rumah, tanpa ribet.',
              subtitle: 'Pesan teknisi tepercaya dan pantau prosesnya.',
              buttonLabel: 'Buat pengajuan servis',
              onPressed: () => _showRequestForm(context),
            ),
          if (role == SerfixRole.customer) const SizedBox(height: 16),
          _SummaryGrid(summary: summary, role: role),
          const SizedBox(height: 22),
          Row(
            children: [
              const Expanded(child: _SectionHeading(title: 'Layanan terbaru')),
              TextButton(
                onPressed: () => onNavigate(1),
                child: const Text('Lihat semua'),
              ),
            ],
          ),
          if (personalRequests.isEmpty)
            const _InfoTile(
              icon: Icons.inbox_outlined,
              title: 'Belum ada pengajuan servis',
              subtitle: 'Pengajuan layanan Anda akan tampil di sini.',
            )
          else
            ...personalRequests.take(3).map((request) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RequestCard(request: request),
                )),
        ],
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary, required this.role});

  final Map<String, dynamic> summary;
  final SerfixRole role;

  @override
  Widget build(BuildContext context) {
    final items = <(String, String, IconData)>[
      ('Menunggu', '${summary['requested'] ?? 0}', Icons.inbox_outlined),
      (
        'Terjadwal',
        '${summary['assigned'] ?? 0}',
        Icons.event_available_outlined
      ),
      ('Dikerjakan', '${summary['in_progress'] ?? 0}', Icons.handyman_outlined),
      ('Selesai', '${summary['completed'] ?? 0}', Icons.task_alt),
    ];
    if (role == SerfixRole.admin || role == SerfixRole.manager) {
      items
        ..add((
          'Teknisi aktif',
          '${summary['technicians'] ?? 0}',
          Icons.engineering_outlined
        ))
        ..add((
          'Stok menipis',
          '${summary['low_stock_parts'] ?? 0}',
          Icons.inventory_2_outlined
        ))
        ..add((
          'Bayar tertunda',
          '${summary['pending_payments'] ?? 0}',
          Icons.payments_outlined
        ))
        ..add((
          'Klaim garansi',
          '${summary['pending_warranty_claims'] ?? 0}',
          Icons.verified_user_outlined
        ));
    }
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.4,
      children: items
          .map((item) => _SummaryCard(
                title: item.$1,
                value: item.$2,
                icon: item.$3,
              ))
          .toList(),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList();

  @override
  Widget build(BuildContext context) {
    final requests = context.watch<SerfixProvider>().requests;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      children: [
        Text('Pesan layanan',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text('Chat langsung dengan pelanggan atau teknisi.'),
        const SizedBox(height: 14),
        if (requests.isEmpty)
          const _InfoTile(
            icon: Icons.chat_bubble_outline,
            title: 'Belum ada percakapan',
            subtitle: 'Pesan akan tersedia setelah ada pengajuan servis.',
          )
        else
          ...requests.map((request) => Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.chat_outlined),
                  ),
                  title: Text(request.service),
                  subtitle: Text(request.technicianName ??
                      request.customerName),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openChat(context, request),
                ),
              )),
      ],
    );
  }

  static Future<void> _openChat(
      BuildContext context, SerfixRequest request) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ChatSheet(request: request),
    );
  }
}

class _ChatSheet extends StatefulWidget {
  const _ChatSheet({required this.request});
  final SerfixRequest request;

  @override
  State<_ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<_ChatSheet> {
  final _messageController = TextEditingController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final messages =
          await context.read<SerfixProvider>().getMessages(widget.request.id);
      if (mounted) setState(() => _messages = messages);
    } catch (_) {
      // Server errors are surfaced only after an attempted send/load action.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    try {
      await context.read<SerfixProvider>().sendMessage(widget.request.id, text);
      _messageController.clear();
      await _load();
    } catch (error) {
      if (mounted) _message(context, error.toString(), error: true);
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
              child: Text('Chat · ${widget.request.service}',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? const Center(child: Text('Belum ada pesan.'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(18),
                          itemCount: _messages.length,
                          itemBuilder: (_, index) {
                            final item = _messages[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                  item['sender_name']?.toString() ?? 'Pengguna',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              subtitle: Text(item['message']?.toString() ?? ''),
                            );
                          },
                        ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration:
                          const InputDecoration(hintText: 'Tulis pesan...'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestList extends StatefulWidget {
  const _RequestList();

  @override
  State<_RequestList> createState() => _RequestListState();
}

class _RequestListState extends State<_RequestList> {
  String _search = '';
  String _status = '';

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SerfixProvider>();
    var requests = provider.requests.where((request) {
      final query = _search.toLowerCase();
      final matchesSearch = query.isEmpty ||
          request.service.toLowerCase().contains(query) ||
          request.device.toLowerCase().contains(query) ||
          request.customerName.toLowerCase().contains(query) ||
          request.id.toString().contains(query);
      final matchesStatus = _status.isEmpty ||
          (request.status.name == _status);
      return matchesSearch && matchesStatus;
    }).toList();
    return RefreshIndicator(
      onRefresh: provider.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        children: [
          Text('Pengajuan dan work order',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text('Jadwal, penugasan teknisi, biaya, dan progres servis.'),
          const SizedBox(height: 14),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Cari layanan atau pelanggan',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) => setState(() => _search = value),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _status.isEmpty ? null : _status,
            decoration: const InputDecoration(labelText: 'Filter status'),
            items: const [
              DropdownMenuItem(value: '', child: Text('Semua status')),
              DropdownMenuItem(value: 'requested', child: Text('Diajukan')),
              DropdownMenuItem(value: 'assigned', child: Text('Ditugaskan')),
              DropdownMenuItem(value: 'inProgress', child: Text('Sedang dikerjakan')),
              DropdownMenuItem(value: 'waitingApproval', child: Text('Menunggu persetujuan')),
              DropdownMenuItem(value: 'completed', child: Text('Selesai')),
              DropdownMenuItem(value: 'cancelled', child: Text('Dibatalkan')),
            ],
            onChanged: (value) => setState(() => _status = value ?? ''),
          ),
          const SizedBox(height: 14),
          if (requests.isEmpty)
            const _InfoTile(
              icon: Icons.inbox_outlined,
              title: 'Belum ada pengajuan',
              subtitle: 'Pengajuan servis akan muncul di sini.',
            )
          else
            ...requests.map((request) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _RequestCard(request: request, detailed: true),
                )),
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request, this.detailed = false});

  final SerfixRequest request;
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SerfixProvider>();
    final role = provider.role;
    final schedule = _dateTime(request.scheduledAt);
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
                const SizedBox(width: 10),
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
            _DetailRow(icon: Icons.schedule, text: schedule),
            const SizedBox(height: 6),
            _DetailRow(
              icon: Icons.person_outline,
              text: role == SerfixRole.customer
                  ? 'Teknisi: ${request.technicianName ?? 'Menunggu penugasan'}'
                  : 'Pelanggan: ${request.customerName}',
            ),
            const SizedBox(height: 6),
            _DetailRow(
                icon: Icons.location_on_outlined,
                text: '${request.area} · ${request.address}'),
            const SizedBox(height: 7),
            Text('Keluhan: ${request.issue}',
                maxLines: detailed ? 4 : 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.receipt_long_outlined, size: 17),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Estimasi ${_money(request.estimate)}'
                    '${request.finalAmount == null ? '' : ' · Total ${_money(request.finalAmount!)}'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (request.paymentStatus == 'paid')
                  const _MiniTag(icon: Icons.check_circle, text: 'Lunas'),
              ],
            ),
            if (request.diagnosis?.isNotEmpty == true ||
                request.workDescription?.isNotEmpty == true ||
                request.parts.isNotEmpty ||
                request.warrantyEndsAt != null) ...[
              const Divider(height: 20),
              if (request.diagnosis?.isNotEmpty == true)
                Text('Diagnosis: ${request.diagnosis}'),
              if (request.workDescription?.isNotEmpty == true)
                Text('Pekerjaan: ${request.workDescription}'),
              if (request.parts.isNotEmpty)
                Text('Sparepart terpakai: ${request.parts.length} item'),
              if (request.warrantyEndsAt != null)
                Text('Garansi sampai ${_date(request.warrantyEndsAt!)}'),
            ],
            if (_hasActions(provider, request)) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 9),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _buildActions(context, provider, role),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _hasActions(SerfixProvider provider, SerfixRequest request) {
    return true;
  }

  List<Widget> _buildActions(
    BuildContext context,
    SerfixProvider provider,
    SerfixRole role,
  ) {
    final actions = <Widget>[];
    actions.add(OutlinedButton.icon(
      onPressed: () => _openChat(context, provider, request),
      icon: const Icon(Icons.chat_outlined, size: 17),
      label: const Text('Chat'),
    ));
    actions.add(OutlinedButton.icon(
      onPressed: () => _openAttachments(context, provider, request),
      icon: const Icon(Icons.attach_file, size: 17),
      label: const Text('Lampiran'),
    ));
    if (role == SerfixRole.admin &&
        request.status == ServiceRequestStatus.requested) {
      actions.add(OutlinedButton.icon(
        onPressed: () => _assign(context, provider, request),
        icon: const Icon(Icons.person_add_alt_1, size: 17),
        label: const Text('Tugaskan teknisi'),
      ));
    }
    if (role == SerfixRole.customer) {
      if (request.status == ServiceRequestStatus.requested ||
          request.status == ServiceRequestStatus.assigned) {
        actions.add(OutlinedButton.icon(
          onPressed: () => _reschedule(context, provider, request),
          icon: const Icon(Icons.edit_calendar_outlined, size: 17),
          label: const Text('Ubah jadwal'),
        ));
      }
      if (request.status != ServiceRequestStatus.requested &&
          request.status != ServiceRequestStatus.cancelled) {
        actions.add(OutlinedButton.icon(
          onPressed: () => _showTracking(context, provider, request),
          icon: const Icon(Icons.location_on_outlined, size: 17),
          label: const Text('Tracking'),
        ));
      }
      if ((request.status == ServiceRequestStatus.assigned ||
              request.status == ServiceRequestStatus.waitingApproval) &&
          !request.estimateApproved) {
        actions.add(FilledButton.tonalIcon(
          onPressed: () =>
              _run(context, () => provider.approveEstimate(request.id)),
          icon: const Icon(Icons.price_check, size: 17),
          label: const Text('Setujui estimasi'),
        ));
      }
      if (request.status == ServiceRequestStatus.requested ||
          request.status == ServiceRequestStatus.assigned ||
          request.status == ServiceRequestStatus.waitingApproval) {
        actions.add(TextButton.icon(
          onPressed: () => _confirmCancel(context, provider, request.id),
          icon: const Icon(Icons.cancel_outlined, size: 17),
          label: const Text('Batalkan'),
        ));
      }
      if (request.status == ServiceRequestStatus.completed &&
          request.paymentStatus != 'paid') {
        actions.add(OutlinedButton.icon(
          onPressed: () => _pay(context, provider, request),
          icon: const Icon(Icons.payments_outlined, size: 17),
          label: const Text('Bayar servis'),
        ));
      }
      if (request.status == ServiceRequestStatus.completed) {
        actions.add(OutlinedButton.icon(
          onPressed: () => _openReview(context, provider, request),
          icon: const Icon(Icons.star_outline, size: 17),
          label: const Text('Beri rating'),
        ));
        actions.add(OutlinedButton.icon(
          onPressed: () => _openInvoice(context, provider, request),
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 17),
          label: const Text('Invoice PDF'),
        ));
      }
    }
    if (role == SerfixRole.technician) {
      if (request.status != ServiceRequestStatus.completed &&
          request.status != ServiceRequestStatus.cancelled) {
        actions.add(OutlinedButton.icon(
          onPressed: () => _updateTracking(context, provider, request),
          icon: const Icon(Icons.near_me_outlined, size: 17),
          label: const Text('Update lokasi'),
        ));
      }
      if (request.status == ServiceRequestStatus.assigned &&
          request.estimateApproved) {
        actions.add(FilledButton.tonalIcon(
          onPressed: () => _run(context, () => provider.startWork(request.id)),
          icon: const Icon(Icons.play_arrow, size: 18),
          label: const Text('Mulai servis'),
        ));
      }
      actions.add(OutlinedButton.icon(
        onPressed: () => _editWorkOrder(context, provider, request),
        icon: const Icon(Icons.assignment_outlined, size: 17),
        label: const Text('Work order'),
      ));
      if (request.status == ServiceRequestStatus.inProgress) {
        actions.add(TextButton.icon(
          onPressed: () => _confirmComplete(context, provider, request),
          icon: const Icon(Icons.task_alt, size: 17),
          label: const Text('Selesaikan servis'),
        ));
      }
    }
    return actions;
  }

  Future<void> _openChat(BuildContext context, SerfixProvider provider,
      SerfixRequest request) async {
    await _MessageList._openChat(context, request);
  }

  Future<void> _openInvoice(BuildContext context, SerfixProvider provider,
      SerfixRequest request) async {
    try {
      final invoice = await provider.getInvoice(request.id);
      if (invoice == null || !context.mounted) return;
      await Printing.layoutPdf(
        name: 'SerFix-Invoice-${request.id}.pdf',
        onLayout: (_) async {
          final pdf = pw.Document();
          final parts = (invoice['parts'] as List? ?? [])
              .whereType<Map>()
              .map(Map<String, dynamic>.from)
              .toList();
          pdf.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              build: (_) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('SERFIX - INVOICE',
                      style: pw.TextStyle(
                          fontSize: 22, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 12),
                  pw.Text('Invoice: SF-${request.id}'),
                  pw.Text('Pelanggan: ${invoice['customer_name']}'),
                  pw.Text('Perangkat: ${invoice['device_name']}'),
                  pw.Text('Layanan: ${invoice['service_name']}'),
                  pw.SizedBox(height: 16),
                  ...parts.map((part) => pw.Text(
                      '- ${part['name']} x${part['quantity']} '
                      '= Rp${part['unit_price']}')),
                  pw.SizedBox(height: 16),
                  pw.Text(
                    'Total: Rp${invoice['final_amount']}',
                    style: pw.TextStyle(
                        fontSize: 16, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 24),
                  pw.Text('Garansi dan rincian teknis tercantum pada sistem SerFix.',
                      style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ),
          );
          return pdf.save();
        },
      );
    } catch (error) {
      if (context.mounted) _message(context, error.toString(), error: true);
    }
  }

  Future<void> _openAttachments(BuildContext context,
      SerfixProvider provider, SerfixRequest request) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final files = Future<List<Map<String, dynamic>>>(
              () => provider.getAttachments(request.id));
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Lampiran bukti servis',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: files,
                    builder: (_, snapshot) {
                      if (!snapshot.hasData) {
                        return const Padding(
                          padding: EdgeInsets.all(18),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snapshot.data!.isEmpty) {
                        return const Text('Belum ada lampiran.');
                      }
                      return SizedBox(
                        height: 180,
                        child: ListView(
                          children: snapshot.data!
                              .map((item) => ListTile(
                                    leading: const Icon(Icons.image_outlined),
                                    title: Text(
                                        item['file_name']?.toString() ?? ''),
                                    subtitle: Text(
                                        '${item['kind']} · ${item['uploader_name']}'),
                                  ))
                              .toList(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        final picked = await ImagePicker()
                            .pickImage(source: ImageSource.gallery);
                        if (picked == null) return;
                        final bytes = await picked.readAsBytes();
                        await provider.uploadAttachment(
                          requestId: request.id,
                          kind: provider.role == SerfixRole.customer
                              ? 'damage'
                              : 'repair',
                          fileName: picked.name,
                          base64: base64Encode(bytes),
                        );
                        setSheetState(() {});
                        if (sheetContext.mounted) {
                          _message(sheetContext, 'Lampiran berhasil diunggah.');
                        }
                      },
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Tambah foto bukti'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _reschedule(BuildContext context, SerfixProvider provider,
      SerfixRequest request) async {
    final date = await showDatePicker(
      context: context,
      initialDate: request.scheduledAt,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(request.scheduledAt),
    );
    if (time == null || !context.mounted) return;
    final scheduled =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    try {
      await provider.proposeReschedule(
          requestId: request.id,
          scheduledAt: scheduled,
          reason: 'Pelanggan mengusulkan jadwal baru.');
      if (context.mounted) _message(context, 'Usulan jadwal dikirim untuk persetujuan.');
    } catch (error) {
      if (context.mounted) _message(context, error.toString(), error: true);
    }
  }

  Future<void> _showTracking(BuildContext context, SerfixProvider provider,
      SerfixRequest request) async {
    try {
      final tracking = await provider.getTracking(request.id);
      if (!context.mounted) return;
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Builder(builder: (sheetContext) {
              final latitude =
                  double.tryParse('${tracking?['latitude']}');
              final longitude =
                  double.tryParse('${tracking?['longitude']}');
              final position = latitude != null && longitude != null
                  ? LatLng(latitude, longitude)
                  : null;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Lokasi teknisi',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  Text('Status: ${tracking?['status'] ?? 'not_started'}'),
                  Text('ETA: ${tracking?['eta_minutes'] ?? '-'} menit'),
                  Text(tracking?['note']?.toString() ?? ''),
                  if (position != null) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 260,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: FlutterMap(
                          options: MapOptions(
                            initialCenter: position,
                            initialZoom: 15,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.autolog.app.autolog',
                            ),
                            MarkerLayer(markers: [
                              Marker(
                                point: position,
                                width: 38,
                                height: 38,
                                child: const Icon(
                                  Icons.location_pin,
                                  color: Color(0xFF0F8B80),
                                  size: 38,
                                ),
                              ),
                            ]),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              );
            }),
          ),
        ),
      );
    } catch (error) {
      if (context.mounted) _message(context, error.toString(), error: true);
    }
  }

  Future<void> _updateTracking(BuildContext context, SerfixProvider provider,
      SerfixRequest request) async {
    String status = 'heading';
    final etaController = TextEditingController(text: '30');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              18, 18, 18, MediaQuery.viewInsetsOf(sheetContext).bottom + 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Update status perjalanan',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              DropdownButtonFormField<String>(
                initialValue: status,
                items: const [
                  DropdownMenuItem(value: 'heading', child: Text('Menuju lokasi')),
                  DropdownMenuItem(value: 'arrived', child: Text('Sudah tiba')),
                  DropdownMenuItem(value: 'working', child: Text('Sedang bekerja')),
                  DropdownMenuItem(value: 'completed', child: Text('Selesai')),
                ],
                onChanged: (value) =>
                    setSheetState(() => status = value ?? 'heading'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: etaController,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Estimasi tiba (menit)'),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    await provider.updateTracking(
                      requestId: request.id,
                      status: status,
                      etaMinutes: int.tryParse(etaController.text),
                      note: status == 'arrived'
                          ? 'Teknisi sudah tiba di lokasi.'
                          : 'Teknisi memperbarui status perjalanan.',
                    );
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                    if (context.mounted) {
                      _message(context, 'Status lokasi diperbarui.');
                    }
                  },
                  child: const Text('Simpan status'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    etaController.dispose();
  }

  Future<void> _openReview(BuildContext context, SerfixProvider provider,
      SerfixRequest request) async {
    int rating = 5;
    final review = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              18, 18, 18, MediaQuery.viewInsetsOf(sheetContext).bottom + 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Rating teknisi',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Row(
                children: List.generate(
                  5,
                  (index) => IconButton(
                    onPressed: () =>
                        setSheetState(() => rating = index + 1),
                    icon: Icon(index < rating
                        ? Icons.star
                        : Icons.star_border),
                    color: Colors.amber,
                  ),
                ),
              ),
              TextField(
                controller: review,
                maxLines: 3,
                decoration:
                    const InputDecoration(labelText: 'Ulasan (opsional)'),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    await provider.saveReview(
                        request.id, rating, review.text.trim());
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                    if (context.mounted) {
                      _message(context, 'Terima kasih atas ulasan Anda.');
                    }
                  },
                  child: const Text('Kirim rating'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    review.dispose();
  }
}

class _RequestFormSheet extends StatefulWidget {
  const _RequestFormSheet();

  @override
  State<_RequestFormSheet> createState() => _RequestFormSheetState();
}

class _RequestFormSheetState extends State<_RequestFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _device = TextEditingController();
  final _issue = TextEditingController();
  final _address = TextEditingController();
  final _area = TextEditingController();
  int? _categoryId;
  late DateTime _scheduledAt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    _scheduledAt = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9);
    final categories = context.read<SerfixProvider>().categories;
    _categoryId = categories.isEmpty ? null : categories.first.id;
  }

  @override
  void dispose() {
    _device.dispose();
    _issue.dispose();
    _address.dispose();
    _area.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<SerfixProvider>().categories;
    if (_categoryId == null && categories.isNotEmpty) {
      _categoryId = categories.first.id;
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 8, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
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
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: _categoryId,
                decoration: const InputDecoration(labelText: 'Jenis layanan'),
                items: categories
                    .map((category) => DropdownMenuItem(
                          value: category.id,
                          child: Text(
                              '${category.name} · ${_money(category.baseFee)}'),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => _categoryId = value),
                validator: (value) =>
                    value == null ? 'Pilih jenis layanan' : null,
              ),
              const SizedBox(height: 10),
              _input(_device, 'Perangkat', 'Contoh: AC Daikin 1 PK'),
              _input(_issue, 'Keluhan', 'Jelaskan kendala yang dialami'),
              _input(_address, 'Alamat servis', 'Alamat lengkap'),
              _input(_area, 'Area layanan', 'Contoh: Bandung'),
              const SizedBox(height: 6),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('Jadwal pilihan'),
                subtitle: Text(_dateTime(_scheduledAt)),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: _pickSchedule,
              ),
              const _InfoTile(
                icon: Icons.price_check_outlined,
                title: 'Biaya transparan',
                subtitle:
                    'Estimasi awal terlihat sebelum servis. Perubahan harga menunggu persetujuan Anda.',
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving || categories.isEmpty ? null : _submit,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send_outlined),
                  label: Text(_saving ? 'Mengirim...' : 'Kirim pengajuan'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _input(TextEditingController controller, String label, String hint) =>
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TextFormField(
          controller: controller,
          decoration: InputDecoration(labelText: label, hintText: hint),
          validator: (value) =>
              value == null || value.trim().isEmpty ? 'Wajib diisi' : null,
        ),
      );

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1),
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt),
    );
    if (!mounted || time == null) return;
    setState(() => _scheduledAt =
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await context.read<SerfixProvider>().createRequest(
            categoryId: _categoryId!,
            deviceName: _device.text.trim(),
            issue: _issue.text.trim(),
            address: _address.text.trim(),
            area: _area.text.trim(),
            scheduledAt: _scheduledAt,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      _message(context, 'Pengajuan servis berhasil dikirim.');
    } catch (error) {
      if (mounted) _message(context, error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _WarrantyList extends StatelessWidget {
  const _WarrantyList();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SerfixProvider>();
    final role = provider.role;
    final warranties = provider.warranties;
    return RefreshIndicator(
      onRefresh: provider.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        children: [
          Text('Garansi dan klaim',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text('Riwayat masa garansi servis dan status klaim.'),
          const SizedBox(height: 14),
          if (warranties.isEmpty)
            const _InfoTile(
              icon: Icons.verified_user_outlined,
              title: 'Belum ada garansi',
              subtitle: 'Garansi servis akan muncul setelah pekerjaan selesai.',
            )
          else
            ...warranties.map((warranty) {
              final claimId = (warranty['claim_id'] as num?)?.toInt();
              final claimStatus = warranty['claim_status'] as String?;
              final warrantyEnd =
                  DateTime.tryParse(warranty['ends_at']?.toString() ?? '');
              final active = warranty['status'] == 'active' &&
                  warrantyEnd != null &&
                  !DateUtils.dateOnly(warrantyEnd)
                      .isBefore(DateUtils.dateOnly(DateTime.now()));
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.verified_user,
                              color: Color(0xFF0F8B80)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${warranty['service_name'] ?? 'Layanan servis'} · ${warranty['device_name'] ?? ''}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          _MiniTag(
                            icon: active
                                ? Icons.check_circle_outline
                                : Icons.history,
                            text:
                                active ? 'Aktif' : (claimStatus ?? 'Berakhir'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                          'Berlaku ${warranty['starts_at']} sampai ${warranty['ends_at']}'),
                      Text(warranty['terms'] as String? ?? ''),
                      if (warranty['claim_description'] != null) ...[
                        const SizedBox(height: 6),
                        Text('Klaim: ${warranty['claim_description']}'),
                        Text('Status klaim: ${claimStatus ?? '—'}'),
                      ],
                      if (role == SerfixRole.customer &&
                          active &&
                          claimStatus != 'pending') ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => _claimWarranty(
                            context,
                            provider,
                            (warranty['id'] as num).toInt(),
                          ),
                          icon: const Icon(Icons.report_problem_outlined),
                          label: const Text('Ajukan klaim garansi'),
                        ),
                      ],
                      if ((role == SerfixRole.admin ||
                              role == SerfixRole.manager) &&
                          claimId != null &&
                          claimStatus == 'pending') ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            FilledButton.tonal(
                              onPressed: () => _run(
                                context,
                                () => provider.decideWarrantyClaim(
                                    claimId, 'approved', ''),
                              ),
                              child: const Text('Setujui klaim'),
                            ),
                            OutlinedButton(
                              onPressed: () => _run(
                                context,
                                () => provider.decideWarrantyClaim(claimId,
                                    'rejected', 'Klaim ditolak admin.'),
                              ),
                              child: const Text('Tolak klaim'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _AccountPage extends StatelessWidget {
  const _AccountPage({required this.user});

  final User? user;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SerfixProvider>();
    final role = provider.role;
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
        const SizedBox(height: 16),
        _InfoTile(
          icon: Icons.badge_outlined,
          title: 'Peran aktif',
          subtitle: role.label,
        ),
        if (role == SerfixRole.technician) ...[
          const SizedBox(height: 10),
          _InventoryList(parts: provider.parts),
        ],
        if (role == SerfixRole.customer) ...[
          const SizedBox(height: 14),
          _AssetList(assets: provider.assets, categories: provider.categories),
        ],
        if (role == SerfixRole.admin || role == SerfixRole.manager) ...[
          const SizedBox(height: 14),
          _TechnicianReportList(report: provider.technicianReport),
          const SizedBox(height: 14),
          _PaymentList(payments: provider.payments, canVerify: true),
          const SizedBox(height: 14),
          _InventoryList(
            parts: provider.parts,
            canEdit: role == SerfixRole.admin,
          ),
          if (role == SerfixRole.admin) ...[
            const SizedBox(height: 14),
            _StaffList(staff: provider.staff, categories: provider.categories),
          ],
        ],
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          ),
          icon: const Icon(Icons.settings_outlined),
          label: const Text('Pengaturan'),
        ),
        OutlinedButton.icon(
          onPressed: () => context.read<AuthProvider>().logout(),
          icon: const Icon(Icons.logout),
          label: const Text('Keluar'),
        ),
      ],
    );
  }
}

class _AssetList extends StatelessWidget {
  const _AssetList({required this.assets, required this.categories});

  final List<Map<String, dynamic>> assets;
  final List<ServiceCategory> categories;

  Future<void> _addAsset(BuildContext context) async {
    final provider = context.read<SerfixProvider>();
    final name = TextEditingController();
    final brand = TextEditingController();
    final model = TextEditingController();
    final serial = TextEditingController();
    int? categoryId;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Tambah aset/ perangkat'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Nama aset')),
                TextField(controller: brand, decoration: const InputDecoration(labelText: 'Merek')),
                TextField(controller: model, decoration: const InputDecoration(labelText: 'Model')),
                TextField(controller: serial, decoration: const InputDecoration(labelText: 'Nomor seri')),
                DropdownButtonFormField<int>(
                  initialValue: categoryId,
                  decoration: const InputDecoration(labelText: 'Kategori layanan'),
                  items: categories
                      .map((category) => DropdownMenuItem(
                          value: category.id, child: Text(category.name)))
                      .toList(),
                  onChanged: (value) => setState(() => categoryId = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Simpan')),
          ],
        ),
      ),
    );
    if (result == true && context.mounted) {
      await _run(context, () => provider.saveAsset(
            name: name.text.trim(),
            categoryId: categoryId,
            brand: brand.text.trim(),
            model: model.text.trim(),
            serialNumber: serial.text.trim(),
          ));
    }
    name.dispose();
    brand.dispose();
    model.dispose();
    serial.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: _SectionHeading(title: 'Perangkat saya')),
                IconButton(
                  tooltip: 'Tambah aset',
                  onPressed: () => _addAsset(context),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            if (assets.isEmpty)
              const Text('Belum ada perangkat yang didaftarkan.')
            else
              ...assets.map((asset) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.devices_outlined),
                    title: Text(asset['name']?.toString() ?? ''),
                    subtitle: Text(
                        '${asset['brand'] ?? ''} ${asset['model'] ?? ''} · '
                        'Layanan berikutnya: ${asset['next_service_at'] ?? 'belum dijadwalkan'}'),
                  )),
          ],
        ),
      ),
    );
  }
}

class _TechnicianReportList extends StatelessWidget {
  const _TechnicianReportList({required this.report});

  final List<Map<String, dynamic>> report;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeading(title: 'Performa teknisi'),
            if (report.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Belum ada data performa teknisi.'),
              )
            else
              ...report.map((item) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.engineering_outlined),
                    title: Text(item['name']?.toString() ?? ''),
                    subtitle: Text(
                        '${item['completed_jobs']} servis · '
                        'Rating ${(double.tryParse('${item['average_rating']}') ?? 0).toStringAsFixed(1)}'),
                    trailing: Text(
                      _money(double.tryParse('${item['revenue']}') ?? 0),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

class _PaymentList extends StatelessWidget {
  const _PaymentList({required this.payments, required this.canVerify});

  final List<Map<String, dynamic>> payments;
  final bool canVerify;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<SerfixProvider>();
    final pending =
        payments.where((payment) => payment['status'] == 'pending').toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeading(title: 'Verifikasi pembayaran'),
            if (pending.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('Tidak ada pembayaran yang menunggu verifikasi.'),
              )
            else
              ...pending.map((payment) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                        '${payment['customer_name']} · ${_money(double.tryParse('${payment['amount']}') ?? 0)}'),
                    subtitle: Text(
                        '${payment['method']} · ${payment['reference'] ?? 'Tanpa referensi'}'),
                    trailing: canVerify
                        ? IconButton(
                            tooltip: 'Tandai sudah diverifikasi',
                            onPressed: () => _run(
                              context,
                              () => provider.verifyPayment(
                                  (payment['id'] as num).toInt(), 'paid'),
                            ),
                            icon: const Icon(Icons.check_circle_outline),
                          )
                        : null,
                  )),
            if (pending.isNotEmpty)
              const Text(
                'Pastikan dana benar-benar diterima sebelum menandai pembayaran lunas.',
                style: TextStyle(fontSize: 11, color: Color(0xFF72808C)),
              ),
          ],
        ),
      ),
    );
  }
}

class _InventoryList extends StatelessWidget {
  const _InventoryList({required this.parts, this.canEdit = false});

  final List<SerfixPart> parts;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: _SectionHeading(title: 'Stok sparepart')),
                if (canEdit)
                  IconButton(
                    tooltip: 'Tambah sparepart',
                    onPressed: () => _editPart(context),
                    icon: const Icon(Icons.add),
                  ),
              ],
            ),
            if (parts.isEmpty)
              const Text('Belum ada data sparepart.')
            else
              ...parts.map((part) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.build_outlined),
                    title: Text(part.name),
                    subtitle: Text('${part.sku} · ${_money(part.unitPrice)}'),
                    trailing: Text(
                      '${part.stock} unit',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: part.stock <= 3 ? Colors.deepOrange : null,
                      ),
                    ),
                    onTap:
                        canEdit ? () => _editPart(context, part: part) : null,
                  )),
          ],
        ),
      ),
    );
  }
}

class _StaffList extends StatelessWidget {
  const _StaffList({required this.staff, required this.categories});

  final List<Map<String, dynamic>> staff;
  final List<ServiceCategory> categories;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: _SectionHeading(title: 'Akun staf')),
                IconButton(
                  tooltip: 'Tambah akun staf',
                  onPressed: () => _createStaff(context, categories),
                  icon: const Icon(Icons.person_add_alt_1),
                ),
              ],
            ),
            if (staff.isEmpty)
              const Text('Belum ada akun staf.')
            else
              ...staff.map((member) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(_roleIcon(_roleFromString(
                        member['role'] as String? ?? 'manager'))),
                    title: Text(member['name'] as String? ?? ''),
                    subtitle: Text(
                        '${member['role']} · ${member['service_area'] ?? member['email']}'),
                  )),
            const Text(
              'Peran pelanggan dibuat melalui registrasi; akun teknisi/admin/manajer dikelola di sini.',
              style: TextStyle(fontSize: 11, color: Color(0xFF72808C)),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkOrderDialog extends StatefulWidget {
  const _WorkOrderDialog({required this.request});

  final SerfixRequest request;

  @override
  State<_WorkOrderDialog> createState() => _WorkOrderDialogState();
}

class _WorkOrderDialogState extends State<_WorkOrderDialog> {
  late final TextEditingController _diagnosis;
  late final TextEditingController _description;
  late final TextEditingController _notes;
  final Map<int, int> _selected = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _diagnosis = TextEditingController(text: widget.request.diagnosis ?? '');
    _description =
        TextEditingController(text: widget.request.workDescription ?? '');
    _notes = TextEditingController(text: widget.request.technicianNotes ?? '');
    for (final part in widget.request.parts) {
      final id = (part['id'] as num?)?.toInt();
      final quantity = (part['quantity'] as num?)?.toInt();
      if (id != null && quantity != null && quantity > 0) {
        _selected[id] = quantity;
      }
    }
  }

  @override
  void dispose() {
    _diagnosis.dispose();
    _description.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parts = context.watch<SerfixProvider>().parts;
    return AlertDialog(
      title: Text('Work order #${widget.request.id}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogInput(_diagnosis, 'Diagnosis'),
              _dialogInput(_description, 'Pekerjaan yang dilakukan'),
              _dialogInput(_notes, 'Catatan teknisi', maxLines: 2),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Sparepart',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              if (parts.isEmpty)
                const Text('Belum ada stok sparepart untuk dipilih.')
              else
                ...parts.map((part) => CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: _selected.containsKey(part.id),
                      title: Text(part.name),
                      subtitle: Text(
                          '${part.stock} tersedia · ${_money(part.unitPrice)}'),
                      onChanged: part.stock <= 0
                          ? null
                          : (selected) => setState(() {
                                if (selected == true) {
                                  _selected[part.id] = 1;
                                } else {
                                  _selected.remove(part.id);
                                }
                              }),
                    )),
              for (final id in _selected.keys.toList())
                Row(
                  children: [
                    Expanded(
                      child: Text(parts
                              .where((part) => part.id == id)
                              .map((part) => part.name)
                              .firstOrNull ??
                          'Sparepart $id'),
                    ),
                    IconButton(
                      onPressed: () => setState(() {
                        final value = _selected[id] ?? 1;
                        if (value > 1) _selected[id] = value - 1;
                      }),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text('${_selected[id]}'),
                    IconButton(
                      onPressed: () => setState(
                          () => _selected[id] = (_selected[id] ?? 0) + 1),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Menyimpan...' : 'Simpan work order'),
        ),
      ],
    );
  }

  Widget _dialogInput(TextEditingController controller, String label,
          {int maxLines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(labelText: label),
        ),
      );

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<SerfixProvider>().saveWorkOrder(
            requestId: widget.request.id,
            diagnosis: _diagnosis.text.trim(),
            description: _description.text.trim(),
            notes: _notes.text.trim(),
            parts: _selected.entries
                .map((entry) => {
                      'part_id': entry.key,
                      'quantity': entry.value,
                    })
                .toList(),
          );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) _message(context, error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _AssignmentDialog extends StatefulWidget {
  const _AssignmentDialog({required this.request});

  final SerfixRequest request;

  @override
  State<_AssignmentDialog> createState() => _AssignmentDialogState();
}

class _AssignmentDialogState extends State<_AssignmentDialog> {
  late DateTime _scheduledAt;
  late Future<List<SerfixTechnician>> _technicians;
  int? _technicianId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _scheduledAt = widget.request.scheduledAt;
    _loadTechnicians();
  }

  void _loadTechnicians() {
    _technicians = context
        .read<SerfixProvider>()
        .findAvailableTechnicians(widget.request, _scheduledAt);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Tugaskan teknisi'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${widget.request.service} · ${widget.request.area}'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Jadwal'),
                subtitle: Text(_dateTime(_scheduledAt)),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: _pickSchedule,
              ),
              FutureBuilder<List<SerfixTechnician>>(
                future: _technicians,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const LinearProgressIndicator();
                  }
                  if (snapshot.hasError) {
                    return Text('Gagal mencari teknisi: ${snapshot.error}');
                  }
                  final available = snapshot.data ?? [];
                  if (available.isEmpty) {
                    return const Text(
                      'Tidak ada teknisi sesuai keahlian/area pada jadwal ini.',
                    );
                  }
                  return DropdownButtonFormField<int>(
                    initialValue:
                        available.any((tech) => tech.id == _technicianId)
                            ? _technicianId
                            : null,
                    decoration: const InputDecoration(labelText: 'Teknisi'),
                    items: available
                        .map((tech) => DropdownMenuItem(
                              value: tech.id,
                              child: Text('${tech.name} · ${tech.area}'),
                            ))
                        .toList(),
                    onChanged: (id) => setState(() => _technicianId = id),
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: _saving || _technicianId == null ? null : _assign,
            child: Text(_saving ? 'Menyimpan...' : 'Konfirmasi'),
          ),
        ],
      );

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt.isBefore(now) ? now : _scheduledAt,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1),
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt),
    );
    if (!mounted || time == null) return;
    setState(() {
      _scheduledAt =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
      _technicianId = null;
      _loadTechnicians();
    });
  }

  Future<void> _assign() async {
    setState(() => _saving = true);
    try {
      await context.read<SerfixProvider>().assignRequest(
            requestId: widget.request.id,
            technicianId: _technicianId!,
            scheduledAt: _scheduledAt,
          );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) _message(context, error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Container(
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
            const Icon(Icons.ac_unit_rounded, color: Colors.white, size: 30),
            const SizedBox(height: 12),
            Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(subtitle, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 14),
            FilledButton.tonal(onPressed: onPressed, child: Text(buttonLabel)),
          ],
        ),
      );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Icon(icon, size: 20, color: const Color(0xFF0F8B80)),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(title, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) =>
      Text(title, style: Theme.of(context).textTheme.titleMedium);
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
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(icon, color: const Color(0xFF0F8B80)),
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle),
        ),
      );
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
    final color = switch (status) {
      ServiceRequestStatus.requested ||
      ServiceRequestStatus.waitingApproval =>
        const Color(0xFFB76500),
      ServiceRequestStatus.assigned => const Color(0xFF2868A8),
      ServiceRequestStatus.inProgress => const Color(0xFF0F8B80),
      ServiceRequestStatus.completed => const Color(0xFF23865F),
      ServiceRequestStatus.cancelled => const Color(0xFF72808C),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style:
            TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF0F716A).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: const Color(0xFF0F716A)),
            const SizedBox(width: 4),
            Text(text,
                style: const TextStyle(fontSize: 11, color: Color(0xFF0F716A))),
          ],
        ),
      );
}

Future<void> _showRequestForm(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _RequestFormSheet(),
    );

Future<void> _assign(
  BuildContext context,
  SerfixProvider provider,
  SerfixRequest request,
) =>
    showDialog<void>(
      context: context,
      builder: (_) => _AssignmentDialog(request: request),
    );

Future<void> _editWorkOrder(
  BuildContext context,
  SerfixProvider provider,
  SerfixRequest request,
) =>
    showDialog<void>(
      context: context,
      builder: (_) => _WorkOrderDialog(request: request),
    );

Future<void> _run(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
    if (context.mounted) _message(context, 'Perubahan berhasil disimpan.');
  } catch (error) {
    if (context.mounted) _message(context, error.toString(), error: true);
  }
}

Future<void> _confirmCancel(
  BuildContext context,
  SerfixProvider provider,
  int requestId,
) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Batalkan pengajuan?'),
      content: const Text('Pengajuan servis ini akan dibatalkan.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Kembali'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Batalkan'),
        ),
      ],
    ),
  );
  if (confirm == true && context.mounted) {
    await _run(context, () => provider.cancelRequest(requestId));
  }
}

Future<void> _confirmComplete(
  BuildContext context,
  SerfixProvider provider,
  SerfixRequest request,
) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Selesaikan servis?'),
      content: const Text(
          'Work order akan ditutup, nilai akhir dikunci, dan garansi diterbitkan bila tersedia.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Kembali'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Selesaikan'),
        ),
      ],
    ),
  );
  if (confirm == true && context.mounted) {
    await _run(context, () => provider.completeWork(request.id));
  }
}

Future<void> _pay(
  BuildContext context,
  SerfixProvider provider,
  SerfixRequest request,
) async {
  String method = 'bank_transfer';
  final reference = TextEditingController();
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(
            'Pembayaran ${_money(request.finalAmount ?? request.estimate)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: method,
              decoration: const InputDecoration(labelText: 'Metode'),
              items: const [
                DropdownMenuItem(
                    value: 'bank_transfer', child: Text('Transfer bank')),
                DropdownMenuItem(value: 'qr', child: Text('QR')),
                DropdownMenuItem(value: 'cash', child: Text('Tunai')),
              ],
              onChanged: (value) => setState(() => method = value!),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reference,
              decoration: const InputDecoration(
                labelText: 'Nomor referensi (opsional)',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'QR adalah integrasi gateway/QRIS. Referensi dibuat otomatis jika dikosongkan.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Kirim pembayaran'),
          ),
        ],
      ),
    ),
  );
  if (result == true && context.mounted) {
    if (method == 'qr') {
      await _run(context, () async {
        final transaction =
            await provider.createGatewayPayment(request.id, 'qris');
        if (context.mounted) {
          showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Pembayaran QRIS'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Referensi: ${transaction['gateway_reference']}'),
                  Text('Jumlah: ${_money((transaction['amount'] as num?)?.toDouble() ?? 0)}'),
                  const SizedBox(height: 8),
                  const Text(
                    'Gateway siap menerima webhook pembayaran. Sambungkan provider QRIS nyata pada konfigurasi backend sebelum produksi.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Tutup'),
                ),
              ],
            ),
          );
        }
      });
    } else {
      await _run(
        context,
        () => provider.createPayment(request.id, method, reference.text.trim()),
      );
    }
  }
  reference.dispose();
}

Future<void> _claimWarranty(
  BuildContext context,
  SerfixProvider provider,
  int warrantyId,
) async {
  final description = TextEditingController();
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Ajukan klaim garansi'),
      content: TextField(
        controller: description,
        maxLines: 4,
        decoration: const InputDecoration(
          labelText: 'Jelaskan kendala',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Kirim klaim'),
        ),
      ],
    ),
  );
  if (result == true && context.mounted && description.text.trim().isNotEmpty) {
    await _run(
      context,
      () => provider.claimWarranty(warrantyId, description.text.trim()),
    );
  }
  description.dispose();
}

Future<void> _editPart(BuildContext context, {SerfixPart? part}) async {
  final provider = context.read<SerfixProvider>();
  final sku = TextEditingController(text: part?.sku ?? '');
  final name = TextEditingController(text: part?.name ?? '');
  final stock = TextEditingController(text: part?.stock.toString() ?? '0');
  final price =
      TextEditingController(text: part?.unitPrice.toStringAsFixed(0) ?? '0');
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(part == null ? 'Tambah sparepart' : 'Ubah sparepart'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
              controller: sku,
              decoration: const InputDecoration(labelText: 'SKU')),
          TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Nama')),
          TextField(
              controller: stock,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Stok')),
          TextField(
              controller: price,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Harga satuan')),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Simpan'),
        ),
      ],
    ),
  );
  if (result == true && context.mounted) {
    final count = int.tryParse(stock.text);
    final unitPrice = double.tryParse(price.text);
    if (count == null ||
        unitPrice == null ||
        sku.text.trim().isEmpty ||
        name.text.trim().isEmpty) {
      _message(context, 'SKU, nama, stok, dan harga harus valid.', error: true);
    } else {
      await _run(
        context,
        () => provider.savePart(
          id: part?.id,
          sku: sku.text.trim(),
          name: name.text.trim(),
          stock: count,
          unitPrice: unitPrice,
        ),
      );
    }
  }
  sku.dispose();
  name.dispose();
  stock.dispose();
  price.dispose();
}

Future<void> _createStaff(
  BuildContext context,
  List<ServiceCategory> categories,
) async {
  final provider = context.read<SerfixProvider>();
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final area = TextEditingController();
  final phone = TextEditingController();
  String role = 'technician';
  final skills = <int>{};
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Buat akun staf'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Nama')),
                TextField(
                    controller: email,
                    decoration: const InputDecoration(labelText: 'Email')),
                TextField(
                    controller: password,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'Password (min. 8 karakter)')),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Peran'),
                  items: const [
                    DropdownMenuItem(
                        value: 'technician', child: Text('Teknisi')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    DropdownMenuItem(value: 'manager', child: Text('Manajer')),
                  ],
                  onChanged: (value) => setState(() => role = value!),
                ),
                if (role == 'technician') ...[
                  TextField(
                      controller: area,
                      decoration:
                          const InputDecoration(labelText: 'Area layanan')),
                  TextField(
                      controller: phone,
                      decoration:
                          const InputDecoration(labelText: 'Nomor telepon')),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text('Keahlian teknisi'),
                    ),
                  ),
                  ...categories.map((category) => CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: skills.contains(category.id),
                        title: Text(category.name),
                        onChanged: (selected) => setState(() {
                          if (selected == true) {
                            skills.add(category.id);
                          } else {
                            skills.remove(category.id);
                          }
                        }),
                      )),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Buat akun'),
          ),
        ],
      ),
    ),
  );
  if (result == true && context.mounted) {
    await _run(
      context,
      () => provider.createStaff(
        name: name.text.trim(),
        email: email.text.trim(),
        password: password.text,
        role: role,
        area: area.text.trim(),
        phone: phone.text.trim(),
        skills: skills.toList(),
      ),
    );
  }
  name.dispose();
  email.dispose();
  password.dispose();
  area.dispose();
  phone.dispose();
}

IconData _roleIcon(SerfixRole role) => switch (role) {
      SerfixRole.customer => Icons.person_outline,
      SerfixRole.technician => Icons.engineering_outlined,
      SerfixRole.admin => Icons.manage_accounts_outlined,
      SerfixRole.manager => Icons.analytics_outlined,
    };

SerfixRole _roleFromString(String role) => switch (role) {
      'technician' => SerfixRole.technician,
      'admin' => SerfixRole.admin,
      'manager' => SerfixRole.manager,
      _ => SerfixRole.customer,
    };

String _subtitle(SerfixRole role) => switch (role) {
      SerfixRole.customer => 'Pantau layanan rumah dalam satu aplikasi.',
      SerfixRole.technician => 'Lihat tugas, jadwal, dan detail work order.',
      SerfixRole.admin => 'Kelola jadwal, teknisi, sparepart, dan pembayaran.',
      SerfixRole.manager => 'Pantau operasional, biaya, dan klaim garansi.',
    };

IconData _serviceIcon(String service) => service.toLowerCase().contains('ac')
    ? Icons.ac_unit
    : Icons.home_repair_service;

String _money(num amount) {
  final value = amount.round().toString();
  final grouped = StringBuffer();
  for (var index = 0; index < value.length; index++) {
    if (index > 0 && (value.length - index) % 3 == 0) grouped.write('.');
    grouped.write(value[index]);
  }
  return 'Rp $grouped';
}

String _date(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

String _dateTime(DateTime date) =>
    '${_date(date)} · ${date.hour.toString().padLeft(2, '0')}.${date.minute.toString().padLeft(2, '0')}';

void _message(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? const Color(0xFFB4232D) : null,
    ),
  );
}
