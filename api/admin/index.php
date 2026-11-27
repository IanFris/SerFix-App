<?php
declare(strict_types=1);

require_once __DIR__ . '/bootstrap.php';
admin_require_login();
$db = admin_db();
$pages = [
    'overview' => 'Ringkasan',
    'requests' => 'Pengajuan servis',
    'staff' => 'Staf & teknisi',
    'parts' => 'Sparepart',
    'payments' => 'Pembayaran',
    'warranties' => 'Klaim garansi',
];
$page = (string)($_GET['page'] ?? 'overview');
if (!isset($pages[$page])) {
    http_response_code(404);
    $page = 'overview';
}
$csrf = admin_csrf_token();
$flash = admin_take_flash();
$search = trim((string)($_GET['q'] ?? ''));
$counts = [
    'customers' => (int)$db->query('SELECT COUNT(*) FROM users WHERE role = "customer"')->fetchColumn(),
    'technicians' => (int)$db->query('SELECT COUNT(*) FROM technician_profiles WHERE is_available = 1')->fetchColumn(),
    'requests' => (int)$db->query('SELECT COUNT(*) FROM service_requests')->fetchColumn(),
    'open' => (int)$db->query('SELECT COUNT(*) FROM service_requests WHERE status IN ("requested", "assigned", "in_progress", "waiting_approval")')->fetchColumn(),
    'pending_assignment' => (int)$db->query('SELECT COUNT(*) FROM service_requests WHERE status = "requested"')->fetchColumn(),
    'waiting_approval' => (int)$db->query('SELECT COUNT(*) FROM service_requests WHERE status = "waiting_approval"')->fetchColumn(),
    'in_progress' => (int)$db->query('SELECT COUNT(*) FROM service_requests WHERE status = "in_progress"')->fetchColumn(),
    'revenue' => (float)$db->query('SELECT COALESCE(SUM(amount), 0) FROM payments WHERE status = "paid"')->fetchColumn(),
];
$categories = $db->query(
    'SELECT id, name FROM service_categories WHERE is_active = 1 ORDER BY name'
)->fetchAll(PDO::FETCH_ASSOC);
$rows = [];
$sql = '';
$params = [];
$searchPattern = '%' . $search . '%';

if ($page === 'requests' || $page === 'overview') {
    $sql = 'SELECT sr.id, customer.name AS customer_name, customer.email,
                   tech.name AS technician_name, sr.technician_id, sr.category_id,
                   sc.name AS service_name, sr.device_name, sr.issue_description,
                   sr.service_area, sr.service_address, sr.requested_at, sr.status,
                   sr.estimate_amount, sr.final_amount
            FROM service_requests sr
            JOIN users customer ON customer.id = sr.customer_id
            LEFT JOIN users tech ON tech.id = sr.technician_id
            JOIN service_categories sc ON sc.id = sr.category_id';
    if ($page === 'requests' && $search !== '') {
        $sql .= ' WHERE customer.name LIKE :name OR customer.email LIKE :email
                  OR sr.device_name LIKE :device OR sr.service_area LIKE :area
                  OR sc.name LIKE :service';
        $params = [
            ':name' => $searchPattern, ':email' => $searchPattern,
            ':device' => $searchPattern, ':area' => $searchPattern,
            ':service' => $searchPattern,
        ];
    }
    $sql .= ' ORDER BY sr.created_at DESC LIMIT 100';
    $stmt = $db->prepare($sql);
    $stmt->execute($params);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
} elseif ($page === 'staff') {
    $sql = 'SELECT u.id, u.name, u.email, u.role, tp.service_area, tp.phone,
                   tp.is_available,
                   GROUP_CONCAT(DISTINCT sc.name ORDER BY sc.name SEPARATOR ", ") AS skills
            FROM users u LEFT JOIN technician_profiles tp ON tp.user_id = u.id
            LEFT JOIN technician_skills ts ON ts.technician_id = u.id
            LEFT JOIN service_categories sc ON sc.id = ts.category_id
            WHERE u.role IN ("technician", "admin", "manager")
            GROUP BY u.id, u.name, u.email, u.role, tp.service_area, tp.phone, tp.is_available
            ORDER BY u.name';
    $rows = $db->query($sql)->fetchAll(PDO::FETCH_ASSOC);
} elseif ($page === 'parts') {
    $rows = $db->query(
        'SELECT id, sku, name, description, stock_quantity, unit_price, is_active
         FROM parts ORDER BY name'
    )->fetchAll(PDO::FETCH_ASSOC);
} elseif ($page === 'payments') {
    $rows = $db->query(
        'SELECT p.id, p.service_request_id, p.amount, p.method, p.status,
                p.reference, p.created_at, customer.name AS customer_name
         FROM payments p JOIN users customer ON customer.id = p.customer_id
         ORDER BY p.created_at DESC LIMIT 100'
    )->fetchAll(PDO::FETCH_ASSOC);
} elseif ($page === 'warranties') {
    $rows = $db->query(
        'SELECT wc.id AS claim_id, wc.description, wc.status AS claim_status,
                wc.decision_notes, wc.created_at AS claimed_at,
                w.id AS warranty_id, w.starts_at, w.ends_at,
                customer.name AS customer_name, sr.device_name, sc.name AS service_name
         FROM warranty_claims wc JOIN warranties w ON w.id = wc.warranty_id
         JOIN users customer ON customer.id = wc.customer_id
         JOIN service_requests sr ON sr.id = w.service_request_id
         JOIN service_categories sc ON sc.id = sr.category_id
         ORDER BY wc.created_at DESC LIMIT 100'
    )->fetchAll(PDO::FETCH_ASSOC);
}

function admin_money(mixed $value): string
{
    return 'Rp ' . number_format((float)$value, 0, ',', '.');
}

function admin_status_label(string $status): string
{
    return match ($status) {
        'requested' => 'Menunggu teknisi',
        'assigned' => 'Terjadwal',
        'in_progress' => 'Sedang dikerjakan',
        'waiting_approval' => 'Menunggu persetujuan',
        'completed' => 'Selesai',
        'cancelled' => 'Dibatalkan',
        default => $status,
    };
}

function admin_page_url(string $page): string
{
    return 'index.php?' . http_build_query(['page' => $page]);
}
?>
<!doctype html>
<html lang="id">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title><?= admin_escape($pages[$page]) ?> | SerFix Admin</title>
  <link rel="stylesheet" href="admin.css">
</head>
<body>
<div class="admin-shell">
  <aside class="sidebar">
    <a class="brand" href="index.php"><span class="brand-mark">S</span> SerFix <small>ADMIN</small></a>
    <p class="side-label">OPERASIONAL</p>
    <nav>
      <?php foreach ($pages as $key => $label): ?>
        <a class="nav-link <?= $page === $key ? 'active' : '' ?>" href="<?= admin_escape(admin_page_url($key)) ?>">
          <span class="nav-dot"></span><?= admin_escape($label) ?>
        </a>
      <?php endforeach; ?>
    </nav>
    <div class="sidebar-bottom">
      <div class="admin-profile"><span class="avatar"><?= admin_escape(strtoupper(substr($_SESSION['admin_email'] ?? 'S', 0, 1))) ?></span><span><strong>Administrator</strong><small><?= admin_escape($_SESSION['admin_email'] ?? '') ?></small></span></div>
      <form method="post" action="logout.php">
        <input type="hidden" name="csrf_token" value="<?= admin_escape($csrf) ?>">
        <button class="logout-button" type="submit">Keluar <span aria-hidden="true">↗</span></button>
      </form>
    </div>
  </aside>
  <main class="main-content">
    <header class="topbar"><span class="breadcrumb">SerFix <span>/</span> <?= admin_escape($pages[$page]) ?></span><span class="secure-label"><span></span> Sesi admin aktif</span></header>
    <section class="page-content">
      <?php if ($flash): ?><div class="notice <?= admin_escape($flash['type']) ?>" role="status"><?= admin_escape($flash['message']) ?></div><?php endif; ?>
      <?php if ($page === 'overview'): ?>
        <section class="dashboard-hero">
          <div class="dashboard-hero-copy">
            <span class="hero-kicker"><span></span> PUSAT KENDALI OPERASIONAL</span>
            <h1>Halo, Admin<span>.</span></h1>
            <p>Pantau layanan, tim teknisi, dan pembayaran SerFix dari satu tempat.</p>
            <div class="hero-actions">
              <a class="hero-button hero-button-primary" href="<?= admin_escape(admin_page_url('requests')) ?>">Lihat pengajuan <span aria-hidden="true">→</span></a>
              <a class="hero-button hero-button-secondary" href="<?= admin_escape(admin_page_url('staff')) ?>">Kelola tim</a>
            </div>
          </div>
          <div class="dashboard-hero-art" aria-hidden="true">
            <div class="hero-orbit hero-orbit-one"></div>
            <div class="hero-orbit hero-orbit-two"></div>
            <div class="hero-mark">S</div>
            <div class="hero-floating-card"><span class="hero-floating-icon">✦</span><span><strong>SerFix Care</strong><small>Rumah nyaman, terlayani.</small></span></div>
            <div class="hero-date"><span>HARI INI</span><strong><?= admin_escape(date('d M Y')) ?></strong></div>
          </div>
        </section>
        <div class="stats-grid">
          <?php foreach ([
              'customers' => ['Pelanggan', '◎', 'staff', 'stat-customer'],
              'technicians' => ['Teknisi tersedia', '◇', 'staff', 'stat-technician'],
              'requests' => ['Total pengajuan', '↻', 'requests', 'stat-request'],
              'open' => ['Layanan aktif', '▤', 'requests', 'stat-active'],
          ] as $key => [$label, $icon, $target, $class]): ?>
            <a class="stat-card <?= admin_escape($class) ?>" href="<?= admin_escape(admin_page_url($target)) ?>"><span class="stat-icon"><?= admin_escape($icon) ?></span><span class="stat-label"><?= admin_escape($label) ?></span><strong><?= number_format($counts[$key]) ?></strong><span class="stat-link">Buka ringkasan <span>→</span></span></a>
          <?php endforeach; ?>
        </div>
        <div class="overview-grid">
          <section class="panel revenue-panel">
            <div class="revenue-heading"><span class="revenue-icon">↗</span><span class="eyebrow">PEMBAYARAN TERVERIFIKASI</span></div>
            <h2><?= admin_escape(admin_money($counts['revenue'])) ?></h2>
            <p class="muted">Total dana yang telah dikonfirmasi admin.</p>
            <a href="<?= admin_escape(admin_page_url('payments')) ?>">Lihat pembayaran <span aria-hidden="true">→</span></a>
            <span class="revenue-mark" aria-hidden="true">Rp</span>
          </section>
          <section class="panel workload-panel">
            <div class="panel-heading"><div><h2>Fokus operasional</h2><p class="muted">Yang perlu dipantau hari ini</p></div><a class="text-link" href="<?= admin_escape(admin_page_url('requests')) ?>">Semua →</a></div>
            <div class="workload-list">
              <a class="workload-row" href="<?= admin_escape(admin_page_url('requests')) ?>">
                <span class="workload-icon workload-icon-amber">↗</span><span class="workload-copy"><strong>Menunggu teknisi</strong><small>Pengajuan baru perlu ditugaskan</small></span><b><?= number_format($counts['pending_assignment']) ?></b>
              </a>
              <a class="workload-row" href="<?= admin_escape(admin_page_url('requests')) ?>">
                <span class="workload-icon workload-icon-blue">Rp</span><span class="workload-copy"><strong>Menunggu persetujuan</strong><small>Estimasi biaya menunggu pelanggan</small></span><b><?= number_format($counts['waiting_approval']) ?></b>
              </a>
              <a class="workload-row" href="<?= admin_escape(admin_page_url('requests')) ?>">
                <span class="workload-icon workload-icon-green">⌁</span><span class="workload-copy"><strong>Sedang dikerjakan</strong><small>Servis yang aktif ditangani</small></span><b><?= number_format($counts['in_progress']) ?></b>
              </a>
            </div>
          </section>
        </div>
        <section class="panel data-panel dashboard-requests">
          <div class="panel-heading"><div><h2>Pengajuan terbaru</h2><p class="muted">Sampai 100 layanan terakhir.</p></div><a class="text-link" href="<?= admin_escape(admin_page_url('requests')) ?>">Semua →</a></div>
          <?php if (!$rows): ?><div class="empty-state">Belum ada pengajuan servis.</div><?php else: ?>
          <div class="table-wrap"><table><thead><tr><th>PELANGGAN</th><th>LAYANAN</th><th>AREA / JADWAL</th><th>STATUS</th><th>ESTIMASI</th></tr></thead><tbody>
          <?php foreach (array_slice($rows, 0, 8) as $row): ?><tr><td><strong><?= admin_escape($row['customer_name']) ?></strong><small><?= admin_escape($row['email']) ?></small></td><td><?= admin_escape($row['service_name']) ?><small><?= admin_escape($row['device_name']) ?></small></td><td><?= admin_escape($row['service_area']) ?><small><?= admin_escape(date('d M Y · H.i', strtotime($row['requested_at']))) ?></small></td><td><span class="tag status-<?= admin_escape($row['status']) ?>"><?= admin_escape(admin_status_label($row['status'])) ?></span></td><td><?= admin_escape(admin_money($row['estimate_amount'])) ?></td></tr><?php endforeach; ?>
          </tbody></table></div><?php endif; ?>
        </section>
      <?php elseif ($page === 'requests'): ?>
        <div class="page-heading"><div><p class="eyebrow">PENJADWALAN</p><h1>Pengajuan servis</h1><p class="muted">Penugasan teknisi divalidasi berdasarkan keahlian, area, dan bentrok jadwal.</p></div></div>
        <section class="panel data-panel">
          <div class="panel-heading"><form class="search-form" method="get"><input type="hidden" name="page" value="requests"><input type="search" name="q" value="<?= admin_escape($search) ?>" placeholder="Cari pelanggan, perangkat, area..."><button class="button secondary" type="submit">Cari</button></form></div>
          <div class="table-wrap"><table><thead><tr><th>PELANGGAN / KELUHAN</th><th>LAYANAN</th><th>AREA / JADWAL</th><th>STATUS</th><th>TEKNISI / AKSI</th></tr></thead><tbody>
          <?php foreach ($rows as $row): ?><tr><td><strong><?= admin_escape($row['customer_name']) ?></strong><small><?= admin_escape($row['device_name']) ?> · <?= admin_escape($row['issue_description']) ?></small></td><td><?= admin_escape($row['service_name']) ?><small><?= admin_escape(admin_money($row['estimate_amount'])) ?></small></td><td><?= admin_escape($row['service_area']) ?><small><?= admin_escape($row['requested_at']) ?></small></td><td><span class="tag"><?= admin_escape($row['status']) ?></span></td><td><?php if ($row['status'] === 'requested'): ?>
            <form class="inline-form" method="post" action="action.php"><input type="hidden" name="csrf_token" value="<?= admin_escape($csrf) ?>"><input type="hidden" name="action" value="assign_request"><input type="hidden" name="request_id" value="<?= (int)$row['id'] ?>"><select name="technician_id" required><option value="">Pilih teknisi yang sesuai</option><?php
              $eligible = $db->prepare('SELECT u.id, u.name FROM technician_profiles tp JOIN users u ON u.id = tp.user_id JOIN technician_skills ts ON ts.technician_id = tp.user_id WHERE tp.is_available = 1 AND LOWER(TRIM(tp.service_area)) = LOWER(TRIM(:area)) AND ts.category_id = :category_id ORDER BY u.name');
              $eligible->execute([':area' => $row['service_area'], ':category_id' => $row['category_id']]);
              foreach ($eligible->fetchAll(PDO::FETCH_ASSOC) as $tech): ?><option value="<?= (int)$tech['id'] ?>"><?= admin_escape($tech['name']) ?></option><?php endforeach; ?></select><input name="scheduled_at" type="datetime-local" value="<?= admin_escape(date('Y-m-d\TH:i', strtotime($row['requested_at']))) ?>" required><button class="button primary" type="submit">Tugaskan</button></form>
          <?php else: ?><?= admin_escape($row['technician_name'] ?? '—') ?><?php endif; ?></td></tr><?php endforeach; ?>
          </tbody></table></div>
        </section>
      <?php elseif ($page === 'staff'): ?>
        <div class="page-heading"><div><p class="eyebrow">AKUN INTERNAL</p><h1>Staf & teknisi</h1><p class="muted">Buat akun dengan peran dan kompetensi sesuai area.</p></div></div>
        <section class="panel data-panel">
          <div class="panel-heading"><h2>Tambah akun staf</h2></div>
          <form class="catalog-form" method="post" action="action.php">
            <input type="hidden" name="csrf_token" value="<?= admin_escape($csrf) ?>"><input type="hidden" name="action" value="create_staff">
            <label>Nama<input name="name" maxlength="100" required></label><label>Email<input name="email" type="email" maxlength="150" required></label><label>Password<input name="password" type="password" minlength="8" required></label>
            <label>Peran<select name="role"><option value="technician">Teknisi</option><option value="admin">Admin aplikasi</option><option value="manager">Manajer</option></select></label>
            <label>Area teknisi<input name="service_area" maxlength="120" placeholder="Contoh: Bandung"></label><label>Telepon<input name="phone" maxlength="30"></label>
            <fieldset><legend>Keahlian teknisi (pilih satu atau lebih)</legend><?php foreach ($categories as $category): ?><label><input type="checkbox" name="skill_ids[]" value="<?= (int)$category['id'] ?>"> <?= admin_escape($category['name']) ?></label><?php endforeach; ?></fieldset>
            <button class="button primary" type="submit">Buat akun</button>
          </form>
          <div class="table-wrap"><table><thead><tr><th>NAMA</th><th>PERAN</th><th>AREA</th><th>KEAHLIAN</th><th>STATUS</th></tr></thead><tbody><?php foreach ($rows as $row): ?><tr><td><strong><?= admin_escape($row['name']) ?></strong><small><?= admin_escape($row['email']) ?></small></td><td><?= admin_escape($row['role']) ?></td><td><?= admin_escape($row['service_area'] ?? '—') ?></td><td><?= admin_escape($row['skills'] ?? '—') ?></td><td><?= $row['is_available'] === null ? '—' : ((int)$row['is_available'] ? 'Tersedia' : 'Nonaktif') ?></td></tr><?php endforeach; ?></tbody></table></div>
        </section>
      <?php elseif ($page === 'parts'): ?>
        <div class="page-heading"><div><p class="eyebrow">INVENTARIS</p><h1>Sparepart</h1><p class="muted">Stok berkurang otomatis saat teknisi mencatat material pada work order.</p></div></div>
        <section class="panel data-panel">
          <div class="panel-heading"><h2>Tambah sparepart</h2></div>
          <form class="catalog-form" method="post" action="action.php">
            <input type="hidden" name="csrf_token" value="<?= admin_escape($csrf) ?>"><input type="hidden" name="action" value="save_part">
            <label>SKU<input name="sku" maxlength="60" required></label><label>Nama<input name="name" maxlength="150" required></label><label>Stok<input name="stock_quantity" type="number" min="0" required></label><label>Harga satuan<input name="unit_price" type="number" min="0" step="0.01" required></label><label>Deskripsi<input name="description" maxlength="500"></label><button class="button primary" type="submit">Tambah</button>
          </form>
          <div class="table-wrap"><table><thead><tr><th>SKU</th><th>SPAREPART</th><th>STOK</th><th>HARGA</th></tr></thead><tbody><?php foreach ($rows as $row): ?><tr><td><?= admin_escape($row['sku']) ?></td><td><?= admin_escape($row['name']) ?><small><?= admin_escape($row['description']) ?></small></td><td><?= (int)$row['stock_quantity'] ?> unit</td><td><?= admin_escape(admin_money($row['unit_price'])) ?></td></tr><?php endforeach; ?></tbody></table></div>
        </section>
      <?php elseif ($page === 'payments'): ?>
        <div class="page-heading"><div><p class="eyebrow">TRANSAKSI</p><h1>Pembayaran</h1><p class="muted">Verifikasi manual hanya setelah dana benar-benar diterima.</p></div></div>
        <section class="panel data-panel"><div class="table-wrap"><table><thead><tr><th>PELANGGAN</th><th>LAYANAN</th><th>METODE / REFERENSI</th><th>JUMLAH</th><th>STATUS / AKSI</th></tr></thead><tbody>
        <?php foreach ($rows as $row): ?><tr><td><?= admin_escape($row['customer_name']) ?><small>#<?= (int)$row['service_request_id'] ?></small></td><td><?= admin_escape($row['created_at']) ?></td><td><?= admin_escape($row['method']) ?><small><?= admin_escape($row['reference'] ?? '—') ?></small></td><td><?= admin_escape(admin_money($row['amount'])) ?></td><td><?= admin_escape($row['status']) ?><?php if ($row['status'] === 'pending'): ?><form method="post" action="action.php"><input type="hidden" name="csrf_token" value="<?= admin_escape($csrf) ?>"><input type="hidden" name="action" value="verify_payment"><input type="hidden" name="id" value="<?= (int)$row['id'] ?>"><button class="button primary" name="decision" value="paid" type="submit">Tandai lunas</button><button class="button danger" name="decision" value="rejected" type="submit">Tolak</button></form><?php endif; ?></td></tr><?php endforeach; ?>
        </tbody></table></div></section>
      <?php else: ?>
        <div class="page-heading"><div><p class="eyebrow">GARANSI LAYANAN</p><h1>Klaim garansi</h1><p class="muted">Tinjau klaim pelanggan dengan catatan keputusan.</p></div></div>
        <section class="panel data-panel"><div class="table-wrap"><table><thead><tr><th>PELANGGAN</th><th>SERVIS</th><th>KLAIM</th><th>GARANSI</th><th>KEPUTUSAN</th></tr></thead><tbody>
        <?php foreach ($rows as $row): ?><tr><td><?= admin_escape($row['customer_name']) ?></td><td><?= admin_escape($row['service_name']) ?><small><?= admin_escape($row['device_name']) ?></small></td><td><?= admin_escape($row['description']) ?><small><?= admin_escape($row['claimed_at']) ?></small></td><td><?= admin_escape($row['starts_at']) ?> — <?= admin_escape($row['ends_at']) ?></td><td><?= admin_escape($row['claim_status']) ?><?php if ($row['claim_status'] === 'pending'): ?><form method="post" action="action.php"><input type="hidden" name="csrf_token" value="<?= admin_escape($csrf) ?>"><input type="hidden" name="action" value="decide_claim"><input type="hidden" name="id" value="<?= (int)$row['claim_id'] ?>"><input name="decision_notes" placeholder="Catatan keputusan"><button class="button primary" name="decision" value="approved" type="submit">Setujui</button><button class="button danger" name="decision" value="rejected" type="submit">Tolak</button></form><?php else: ?><small><?= admin_escape($row['decision_notes'] ?? '') ?></small><?php endif; ?></td></tr><?php endforeach; ?>
        </tbody></table></div></section>
      <?php endif; ?>
    </section>
  </main>
</div>
</body>
</html>
