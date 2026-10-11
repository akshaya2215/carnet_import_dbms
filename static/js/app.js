// app.js — Indian Vehicle Import Eligibility System

// ── Sidebar toggle (mobile) ───────────────────────────────
const sidebarToggle = document.getElementById('sidebarToggle');
const sidebar = document.querySelector('.sidebar');
if (sidebarToggle && sidebar) {
  sidebarToggle.addEventListener('click', () => {
    sidebar.classList.toggle('open');
  });
}

// ── Mobile nav toggle (public) ───────────────────────────
const navToggle = document.getElementById('navToggle');
const pubNav = document.querySelector('.pub-nav');
if (navToggle && pubNav) {
  navToggle.addEventListener('click', () => {
    pubNav.classList.toggle('open');
  });
}

// ── Delete confirmation modal ─────────────────────────────
// Each delete form has data-confirm="Message to show"
document.querySelectorAll('form[data-confirm]').forEach(form => {
  form.addEventListener('submit', e => {
    const msg = form.getAttribute('data-confirm') || 'Delete this record?';
    if (!confirm(msg)) e.preventDefault();
  });
});

// ── Auto-dismiss flash alerts after 6 s ──────────────────
document.querySelectorAll('.flash-alert').forEach(el => {
  setTimeout(() => {
    el.style.transition = 'opacity .4s';
    el.style.opacity = '0';
    setTimeout(() => el.remove(), 420);
  }, 6000);
});

// ── Carnet section toggle on /check ──────────────────────
const importSel = document.getElementById('importTypeSelect');
const carnetSec = document.getElementById('carnetSection');
if (importSel && carnetSec) {
  function toggleCarnet() {
    const txt = importSel.options[importSel.selectedIndex]?.text || '';
    carnetSec.style.display = txt.includes('TEMPORARY_CARNET') ? '' : 'none';
  }
  importSel.addEventListener('change', toggleCarnet);
  toggleCarnet();
}

// ── Prevent double-submit on check form ──────────────────
const checkForm = document.getElementById('checkForm');
const submitBtn = document.getElementById('submitBtn');
if (checkForm && submitBtn) {
  checkForm.addEventListener('submit', () => {
    submitBtn.disabled = true;
    submitBtn.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Evaluating…';
  });
}

// ── CSV export ────────────────────────────────────────────
document.querySelectorAll('.btn-export-csv').forEach(btn => {
  btn.addEventListener('click', () => {
    const tableId = btn.getAttribute('data-table');
    const table = document.getElementById(tableId);
    if (!table) return;
    const rows = [...table.querySelectorAll('tr')];
    const csv = rows.map(row =>
      [...row.querySelectorAll('th,td')]
        .map(cell => `"${cell.innerText.replace(/"/g, '""')}"`)
        .join(',')
    ).join('\n');
    const a = document.createElement('a');
    a.href = 'data:text/csv;charset=utf-8,' + encodeURIComponent(csv);
    a.download = (tableId || 'export') + '.csv';
    a.click();
  });
});

// ── Rule toggle submit (form switches) ───────────────────
document.querySelectorAll('.rule-toggle').forEach(sw => {
  sw.addEventListener('change', () => sw.closest('form').submit());
});

// ── Table client search ───────────────────────────────────
document.querySelectorAll('[data-search-table]').forEach(input => {
  const tableId = input.getAttribute('data-search-table');
  const tbody = document.querySelector(`#${tableId} tbody`);
  if (!tbody) return;
  input.addEventListener('input', () => {
    const q = input.value.toLowerCase();
    tbody.querySelectorAll('tr').forEach(row => {
      row.style.display = row.textContent.toLowerCase().includes(q) ? '' : 'none';
    });
  });
});
