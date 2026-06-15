let tables = [];
let selectedTable = null;
let totalRows = 0;
let columns = [];
let offset = 0;

const tableListEl = document.getElementById('tableList');
const tableSearchEl = document.getElementById('tableSearch');
const tableHeadEl = document.getElementById('tableHead');
const tableBodyEl = document.getElementById('tableBody');
const tableTitleEl = document.getElementById('tableTitle');
const pageInfoEl = document.getElementById('pageInfo');
const pageSizeEl = document.getElementById('pageSize');
const orderDirectionEl = document.getElementById('orderDirection');
const refreshBtnEl = document.getElementById('refreshBtn');
const prevBtnEl = document.getElementById('prevBtn');
const nextBtnEl = document.getElementById('nextBtn');
const summaryTableEl = document.getElementById('summaryTable');
const summaryTotalRowsEl = document.getElementById('summaryTotalRows');
const summaryColumnsEl = document.getElementById('summaryColumns');
const healthBadgeEl = document.getElementById('healthBadge');

function pageSize() {
  return Number(pageSizeEl.value || 50);
}

function formatCell(value) {
  if (value === null || value === undefined) return '<span class="null">NULL</span>';
  if (typeof value === 'object') return `<div class="json">${escapeHtml(JSON.stringify(value, null, 2))}</div>`;
  return escapeHtml(String(value));
}

function escapeHtml(text) {
  return text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function updatePager() {
  const page = Math.floor(offset / pageSize()) + 1;
  const totalPages = Math.max(1, Math.ceil(totalRows / pageSize()));
  pageInfoEl.textContent = `Page ${page} of ${totalPages}`;
  prevBtnEl.disabled = offset <= 0;
  nextBtnEl.disabled = offset + pageSize() >= totalRows;
}

function updateSummary() {
  summaryTableEl.textContent = selectedTable || '-';
  summaryTotalRowsEl.textContent = selectedTable ? totalRows.toLocaleString() : '-';
  summaryColumnsEl.textContent = selectedTable ? columns.length.toString() : '-';
}

function renderTableList() {
  const query = tableSearchEl.value.trim().toLowerCase();
  const filtered = tables.filter((t) => t.table_name.toLowerCase().includes(query));

  tableListEl.innerHTML = filtered
    .map((t) => {
      const active = t.table_name === selectedTable ? 'active' : '';
      return `<li class="${active}" data-table="${t.table_name}">
        <span>${t.table_name}</span>
        <span class="count">~${Number(t.estimated_rows).toLocaleString()}</span>
      </li>`;
    })
    .join('');

  for (const li of tableListEl.querySelectorAll('li')) {
    li.addEventListener('click', () => {
      offset = 0;
      loadTable(li.dataset.table);
    });
  }
}

async function checkHealth() {
  try {
    const res = await fetch('/api/health');
    const data = await res.json();
    healthBadgeEl.textContent = `Connected: ${data.database}@${data.host}`;
    healthBadgeEl.style.borderColor = '#24c08a';
  } catch {
    healthBadgeEl.textContent = 'Database connection failed';
    healthBadgeEl.style.borderColor = '#ff8ea6';
  }
}

async function loadTables() {
  const res = await fetch('/api/tables');
  const data = await res.json();
  tables = data.tables || [];
  renderTableList();
}

async function loadTableMeta(table) {
  const res = await fetch(`/api/tables/${encodeURIComponent(table)}/meta`);
  const data = await res.json();
  totalRows = data.totalRows || 0;
  columns = (data.columns || []).map((c) => c.column_name);
  updateSummary();
}

async function loadTableRows(table) {
  const params = new URLSearchParams({
    limit: String(pageSize()),
    offset: String(offset),
    orderDir: orderDirectionEl.value,
  });
  const res = await fetch(`/api/tables/${encodeURIComponent(table)}/rows?${params.toString()}`);
  const data = await res.json();

  tableHeadEl.innerHTML = `<tr>${data.columns.map((c) => `<th>${escapeHtml(c)}</th>`).join('')}</tr>`;
  tableBodyEl.innerHTML =
    data.rows.length === 0
      ? `<tr><td colspan="${Math.max(data.columns.length, 1)}">No rows found.</td></tr>`
      : data.rows
          .map(
            (row) =>
              `<tr>${data.columns.map((col) => `<td>${formatCell(row[col])}</td>`).join('')}</tr>`,
          )
          .join('');

  updatePager();
}

async function loadTable(table) {
  selectedTable = table;
  renderTableList();
  tableTitleEl.textContent = `Table: ${table}`;
  await loadTableMeta(table);
  await loadTableRows(table);
}

tableSearchEl.addEventListener('input', renderTableList);

refreshBtnEl.addEventListener('click', async () => {
  await loadTables();
  if (selectedTable) await loadTable(selectedTable);
});

pageSizeEl.addEventListener('change', async () => {
  offset = 0;
  if (selectedTable) await loadTableRows(selectedTable);
});

orderDirectionEl.addEventListener('change', async () => {
  offset = 0;
  if (selectedTable) await loadTableRows(selectedTable);
});

prevBtnEl.addEventListener('click', async () => {
  if (!selectedTable) return;
  offset = Math.max(0, offset - pageSize());
  await loadTableRows(selectedTable);
});

nextBtnEl.addEventListener('click', async () => {
  if (!selectedTable) return;
  offset += pageSize();
  await loadTableRows(selectedTable);
});

async function init() {
  await checkHealth();
  await loadTables();
  if (tables.length > 0) await loadTable(tables[0].table_name);
}

init();
