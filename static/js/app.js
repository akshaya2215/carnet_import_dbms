// app.js — Indian Vehicle Import Eligibility & Customs Compliance Portal

document.addEventListener('DOMContentLoaded', () => {
  // ── 1. Admin Sidebar Toggle (Mobile) ───────────────────────
  const sidebarToggle = document.getElementById('sidebarToggle');
  const sidebar = document.getElementById('adminSidebar');
  if (sidebarToggle && sidebar) {
    sidebarToggle.addEventListener('click', (e) => {
      e.stopPropagation();
      sidebar.classList.toggle('open');
    });

    // Close when clicking outside on mobile
    document.addEventListener('click', (e) => {
      if (sidebar.classList.contains('open') && !sidebar.contains(e.target) && e.target !== sidebarToggle) {
        sidebar.classList.remove('open');
      }
    });
  }

  // ── 2. Public Topbar Nav Toggle (Mobile) ───────────────────
  const navToggle = document.getElementById('navToggle');
  const pubNav = document.getElementById('pubNav');
  if (navToggle && pubNav) {
    navToggle.addEventListener('click', (e) => {
      e.stopPropagation();
      pubNav.classList.toggle('open');
    });

    document.addEventListener('click', (e) => {
      if (pubNav.classList.contains('open') && !pubNav.contains(e.target) && e.target !== navToggle) {
        pubNav.classList.remove('open');
      }
    });
  }

  // ── 3. Carnet Section Toggle on /check ─────────────────────
  const importSel = document.getElementById('importTypeSelect');
  const carnetSec = document.getElementById('carnetSection');
  if (importSel && carnetSec) {
    function evaluateCarnetVisibility() {
      const selectedOption = importSel.options[importSel.selectedIndex];
      const text = (selectedOption ? selectedOption.text : '').toUpperCase();
      // If category contains CARNET or TEMPORARY
      if (text.includes('CARNET') || text.includes('TEMPORARY')) {
        carnetSec.style.display = 'block';
      } else {
        carnetSec.style.display = 'none';
      }
    }
    importSel.addEventListener('change', evaluateCarnetVisibility);
    evaluateCarnetVisibility();
  }

  // ── 4. Form Submission Guard ───────────────────────────────
  const checkForm = document.getElementById('checkForm');
  const submitBtn = document.getElementById('submitBtn');
  if (checkForm && submitBtn) {
    checkForm.addEventListener('submit', (e) => {
      if (checkForm.checkValidity && !checkForm.checkValidity()) {
        // Let HTML5 browser validation report invalid fields
        return;
      }
      submitBtn.disabled = true;
      submitBtn.innerHTML = '<span class="spinner-border spinner-border-sm me-2" role="status" aria-hidden="true"></span>Evaluating eligibility…';
    });
  }

  // ── 5. Delete Confirmations ────────────────────────────────
  document.querySelectorAll('form[data-confirm]').forEach(form => {
    form.addEventListener('submit', (e) => {
      const msg = form.getAttribute('data-confirm') || 'Are you sure you want to delete this record?';
      if (!window.confirm(msg)) {
        e.preventDefault();
      }
    });
  });

  // ── 6. Client-Side Table CSV Export ────────────────────────
  document.querySelectorAll('.btn-export-csv').forEach(btn => {
    btn.addEventListener('click', () => {
      const tableId = btn.getAttribute('data-table');
      const table = document.getElementById(tableId);
      if (!table) return;

      const rows = Array.from(table.querySelectorAll('tr'));
      const csvLines = rows.map(row => {
        const cells = Array.from(row.querySelectorAll('th, td'));
        // Exclude action columns with no text or only buttons
        return cells
          .filter(cell => !cell.classList.contains('no-export'))
          .map(cell => {
            let val = cell.innerText.trim().replace(/\r?\n|\r/g, ' ');
            return `"${val.replace(/"/g, '""')}"`;
          })
          .join(',');
      });

      const csvContent = csvLines.join('\r\n');
      const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.setAttribute('href', url);
      link.setAttribute('download', `${tableId || 'customs-report'}-${new Date().toISOString().slice(0, 10)}.csv`);
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      URL.revokeObjectURL(url);
    });
  });

  // ── 7. Instant Rule Toggle ─────────────────────────────────
  document.querySelectorAll('.rule-toggle').forEach(checkbox => {
    checkbox.addEventListener('change', () => {
      const form = checkbox.closest('form');
      if (form) form.submit();
    });
  });

  // ── 8. Client-Side Table Search / Filter ───────────────────
  document.querySelectorAll('[data-search-table]').forEach(input => {
    const tableId = input.getAttribute('data-search-table');
    const table = document.getElementById(tableId);
    if (!table) return;
    const tbody = table.querySelector('tbody');
    if (!tbody) return;

    input.addEventListener('input', () => {
      const query = input.value.trim().toLowerCase();
      const rows = tbody.querySelectorAll('tr');
      rows.forEach(row => {
        const text = row.textContent.toLowerCase();
        row.style.display = text.includes(query) ? '' : 'none';
      });
    });
  });

  // ── 9. Auto-dismiss Flash Alerts ───────────────────────────
  document.querySelectorAll('.flash-alert').forEach(alert => {
    setTimeout(() => {
      alert.style.transition = 'opacity 0.3s ease, transform 0.3s ease';
      alert.style.opacity = '0';
      alert.style.transform = 'translateY(-4px)';
      setTimeout(() => alert.remove(), 320);
    }, 6000);
  });
});
