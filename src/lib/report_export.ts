/**
 * Report files made in the browser (nothing is sent to another service):
 *  - Excel (.xlsx) with a title block, styled header, number formats, filters, frozen header and totals (exceljs)
 *  - PDF (A4, portrait or landscape) laid out as HTML pages and rendered exactly as the screen draws them, so Arabic text,
 *    right-to-left layout and the app fonts are correct; header, filters, page numbers and a confidentiality line on every page
 *  - PowerPoint board pack with native, editable charts (pptxgenjs)
 * The libraries are loaded only when a file is made.
 */
import type { Lang } from './api';
import { cellText, codeLabel, filterLine, reportFileName, reportTotals, type BoardPack, type ReportColumn, type ReportParams, type ReportResult } from './api_rep';
import { saveFile } from './native';

export type Labeler = (k: string) => string;

const PETROL = '0B5A6B';
const MAX_PDF_ROWS = 1500;

function colLabel(c: ReportColumn, lang: Lang): string { return lang === 'ar' ? c.ar : c.en; }
function titleOf(r: ReportResult, lang: Lang): string { return lang === 'ar' ? r.name_ar : r.name_en; }
function entityName(r: ReportResult, lang: Lang): string { return r.entity ? (lang === 'ar' ? (r.entity.name_ar ?? r.entity.name_en) : r.entity.name_en) : ''; }
function stamp(iso: string): string {
  const d = new Date(iso);
  const p = (n: number) => String(n).padStart(2, '0');
  return `${p(d.getDate())}/${p(d.getMonth() + 1)}/${d.getFullYear()} ${p(d.getHours())}:${p(d.getMinutes())}`;
}

// ============================================================================ Excel
export async function exportExcel(r: ReportResult, params: ReportParams, lang: Lang, lbl: Labeler): Promise<void> {
  const ExcelJS = (await import('exceljs')).default;
  const wb = new ExcelJS.Workbook();
  wb.creator = 'AACT HRMS'; wb.created = new Date(r.generated_at);
  const sheetName = (r.code + ' ' + r.name_en).replace(/[\\/?*[\]:]/g, ' ').slice(0, 31);
  const cols = r.columns;
  const n = Math.max(cols.length, 1);
  const ws = wb.addWorksheet(sheetName, {
    pageSetup: { paperSize: 9, orientation: cols.length > 7 ? 'landscape' : 'portrait', fitToPage: true, fitToWidth: 1, fitToHeight: 0,
      margins: { left: 0.4, right: 0.4, top: 0.5, bottom: 0.5, header: 0.2, footer: 0.2 } },
    headerFooter: { oddFooter: `&L${lbl('rp.confidential')}&R&P / &N` },
  });
  const title = ws.addRow([titleOf(r, lang)]);
  title.font = { bold: true, size: 15, color: { argb: 'FF' + PETROL } };
  ws.mergeCells(1, 1, 1, n);
  const info = [entityName(r, lang), filterLine(r, params, lang, lbl), `${lbl('rp.generated')} ${stamp(r.generated_at)} · ${r.generated_by ?? ''}`];
  for (const line of info) { const row = ws.addRow([line]); row.font = { size: 10, color: { argb: 'FF5E6E73' } }; ws.mergeCells(row.number, 1, row.number, n); }
  ws.addRow([]);
  const head = ws.addRow(cols.map((c) => colLabel(c, lang)));
  head.eachCell((cell) => {
    cell.font = { bold: true, color: { argb: 'FFFFFFFF' } };
    cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF' + PETROL } };
    cell.alignment = { vertical: 'middle', wrapText: true };
    cell.border = { bottom: { style: 'thin', color: { argb: 'FF08434F' } } };
  });
  head.height = 30;
  const fmt = (c: ReportColumn) => (c.t === 'money' ? '#,##0.000' : c.t === 'num' ? '#,##0.##' : c.t === 'int' ? '#,##0' : c.t === 'pct' ? '0.0"%"' : c.t === 'date' ? 'dd/mm/yyyy' : '@');
  for (const row of r.rows) {
    const values = cols.map((c) => {
      const v = row[c.k];
      if (v === null || v === undefined || v === '') return null;
      if (c.t === 'date') { const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(v)); return m ? new Date(Date.UTC(+m[1], +m[2] - 1, +m[3])) : String(v); }
      if (c.t === 'text') return typeof v === 'string' ? codeLabel(v, lang) : v;
      return Number(v);
    });
    ws.addRow(values);
  }
  const totals = reportTotals(cols, r.rows);
  if (totals) {
    const tr = ws.addRow(cols.map((c, i) => (i === 0 ? lbl('rp.total') : c.k in totals ? totals[c.k] : null)));
    tr.font = { bold: true };
    tr.eachCell((cell) => { cell.border = { top: { style: 'thin' } }; cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFEEF3F4' } }; });
  }
  cols.forEach((c, i) => {
    const col = ws.getColumn(i + 1);
    col.numFmt = fmt(c);
    const longest = Math.max(colLabel(c, lang).length, ...r.rows.slice(0, 500).map((row) => cellText(row[c.k], c.t, lang).length));
    col.width = Math.min(Math.max(longest + 2, c.t === 'text' ? 12 : 10), 48);
    if (c.t !== 'text') col.alignment = { horizontal: 'right' };
  });
  ws.autoFilter = { from: { row: head.number, column: 1 }, to: { row: head.number, column: n } };
  ws.views = [{ state: 'frozen', ySplit: head.number, rightToLeft: lang === 'ar' }];
  const note = ws.addRow([lbl('rp.confidential')]);
  note.font = { italic: true, size: 9, color: { argb: 'FF5E6E73' } };
  const buf = await wb.xlsx.writeBuffer();
  await saveFile(reportFileName(r, params, 'xlsx'), new Blob([buf], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }));
}

// ============================================================================ PDF
function el<K extends keyof HTMLElementTagNameMap>(tag: K, cls?: string, text?: string): HTMLElementTagNameMap[K] {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined) e.textContent = text;
  return e;
}

export async function exportPdf(r: ReportResult, params: ReportParams, lang: Lang, lbl: Labeler): Promise<void> {
  const [{ toJpeg, getFontEmbedCSS }, { jsPDF }] = await Promise.all([import('html-to-image'), import('jspdf')]);
  const landscape = r.columns.length > 7;
  const W = landscape ? 1123 : 794, H = landscape ? 794 : 1123;
  const host = el('div', 'rp-pdf-host');
  host.setAttribute('aria-hidden', 'true');
  document.body.appendChild(host);
  try {
    const rows = r.rows.slice(0, MAX_PDF_ROWS);
    const totals = reportTotals(r.columns, r.rows);
    const pages: HTMLElement[] = [];
    const makeHead = () => {
      const thead = el('thead'); const tr = el('tr');
      for (const c of r.columns) { const th = el('th', c.t === 'text' ? '' : 'n', colLabel(c, lang)); tr.appendChild(th); }
      thead.appendChild(tr); return thead;
    };
    const newPage = (first: boolean) => {
      const page = el('div', 'rp-pdf-page');
      page.dir = lang === 'ar' ? 'rtl' : 'ltr';
      page.style.width = `${W}px`; page.style.height = `${H}px`;
      const head = el('header', 'rp-pdf-head');
      const left = el('div');
      left.appendChild(el('div', 'rp-pdf-entity', entityName(r, lang)));
      left.appendChild(el('h1', '', titleOf(r, lang)));
      if (first) left.appendChild(el('div', 'rp-pdf-filters', filterLine(r, params, lang, lbl)));
      head.appendChild(left);
      head.appendChild(el('div', 'rp-pdf-brand', 'AACT HRMS'));
      page.appendChild(head);
      const body = el('div', 'rp-pdf-body');
      const table = el('table'); table.appendChild(makeHead()); const tbody = el('tbody'); table.appendChild(tbody);
      body.appendChild(table); page.appendChild(body);
      const foot = el('footer', 'rp-pdf-foot');
      foot.appendChild(el('span', '', `${lbl('rp.generated')} ${stamp(r.generated_at)} · ${r.generated_by ?? ''}`));
      foot.appendChild(el('span', 'rp-pdf-conf', lbl('rp.confidential')));
      const pageNo = el('span', 'rp-pdf-pageno', ''); pageNo.dir = 'ltr'; foot.appendChild(pageNo);
      page.appendChild(foot);
      host.appendChild(page); pages.push(page);
      return { body, tbody };
    };
    let cur = newPage(true);
    const addRow = (cells: string[], cls?: string) => {
      const tr = el('tr', cls);
      cells.forEach((v, i) => tr.appendChild(el('td', r.columns[i].t === 'text' ? '' : 'n', v)));
      cur.tbody.appendChild(tr);
      if (cur.body.scrollHeight > cur.body.clientHeight && cur.tbody.children.length > 1) {
        tr.remove(); cur = newPage(false); cur.tbody.appendChild(tr);
      }
    };
    if (!rows.length) addRow([lbl('rp.no_rows'), ...r.columns.slice(1).map(() => '')]);
    for (const row of rows) addRow(r.columns.map((c) => cellText(row[c.k], c.t, lang)));
    if (totals) addRow(r.columns.map((c, i) => (i === 0 ? lbl('rp.total') : c.k in totals ? cellText(totals[c.k], c.t, lang) : '')), 'tot');
    if (r.rows.length > MAX_PDF_ROWS) addRow([lbl('rp.pdf_cut').replace('{n}', String(MAX_PDF_ROWS)), ...r.columns.slice(1).map(() => '')], 'note');
    pages.forEach((p, i) => { p.querySelector('.rp-pdf-pageno')!.textContent = `${i + 1} / ${pages.length}`; });

    const pdf = new jsPDF({ orientation: landscape ? 'landscape' : 'portrait', unit: 'pt', format: 'a4', compress: true });
    pdf.setProperties({ title: titleOf(r, lang), subject: entityName(r, lang), creator: 'AACT HRMS', author: r.generated_by ?? '' });
    const pw = pdf.internal.pageSize.getWidth(), ph = pdf.internal.pageSize.getHeight();
    const fontEmbedCSS = await getFontEmbedCSS(pages[0]);
    for (let i = 0; i < pages.length; i++) {
      const img = await toJpeg(pages[i], { quality: 0.86, pixelRatio: 1.75, backgroundColor: '#ffffff', fontEmbedCSS, width: W, height: H });
      if (i > 0) pdf.addPage();
      pdf.addImage(img, 'JPEG', 0, 0, pw, ph, undefined, 'FAST');
    }
    await saveFile(reportFileName(r, params, 'pdf'), pdf.output('blob'));
  } finally {
    host.remove();
  }
}

// ============================================================================ PowerPoint board pack
export async function exportBoardPack(b: BoardPack, lang: Lang, lbl: Labeler): Promise<void> {
  const PptxGenJS = (await import('pptxgenjs')).default;
  const pptx = new PptxGenJS();
  pptx.layout = 'LAYOUT_WIDE';
  pptx.rtlMode = lang === 'ar';
  pptx.title = lbl('bp.title');
  pptx.company = b.entity.name_en;
  const ar = lang === 'ar';
  const L = (en: string | null | undefined, a: string | null | undefined) => (ar ? (a || en || '') : (en || ''));
  const font = 'Arial';
  const C = { petrol: PETROL, ink: '1B2A2F', muted: '5E6E73', page: 'F3F5F6', brass: 'C9A24D', deep: '0D2429', red: 'B4442F', green: '2F7D5B' };
  const align = ar ? 'right' : 'left';
  const e = b.exec;
  const last = e.months[e.months.length - 1];
  const lastPay = [...e.months].reverse().find((m) => m.payroll_cost != null) ?? null;
  const months = e.months.map((m) => m.month);
  const pct = (v: number | null | undefined) => (v == null ? '—' : `${v}%`);
  const money = (v: number | null | undefined) => (v == null ? '—' : v.toLocaleString('en-US', { maximumFractionDigits: 0 }));
  const sumL = e.months.reduce((a, m) => a + m.leavers, 0);
  const avgHc = e.months.reduce((a, m) => a + m.headcount, 0) / Math.max(e.months.length, 1);
  const turnover = avgHc ? Math.round((1000 * sumL) / avgHc) / 10 : null;
  const absence = (() => { const w = e.months.reduce((a, m) => a + m.worked_days, 0); return w ? Math.round((1000 * e.months.reduce((a, m) => a + m.absent_days, 0)) / w) / 10 : null; })();
  const footer = (s: ReturnType<typeof pptx.addSlide>, n: number) => {
    s.addText(`${L(b.entity.name_en, b.entity.name_ar)} · ${lbl('bp.title')} · ${lbl('rp.confidential')}`, { x: 0.5, y: 7.0, w: 10, h: 0.3, fontFace: font, fontSize: 9, color: C.muted, align });
    s.addText(String(n), { x: 12.3, y: 7.0, w: 0.6, h: 0.3, fontFace: font, fontSize: 9, color: C.muted, align: 'right' });
  };
  const titleSlide = (s: ReturnType<typeof pptx.addSlide>, t: string, sub?: string) => {
    s.background = { color: 'FFFFFF' };
    s.addText(t, { x: 0.5, y: 0.35, w: 12.3, h: 0.7, fontFace: font, fontSize: 28, bold: true, color: C.deep, align });
    if (sub) s.addText(sub, { x: 0.5, y: 1.0, w: 12.3, h: 0.4, fontFace: font, fontSize: 14, color: C.muted, align });
  };
  const chartBase = { catAxisLabelColor: C.muted, valAxisLabelColor: C.muted, catAxisLabelFontFace: font, valAxisLabelFontFace: font, catAxisLabelFontSize: 10,
    valAxisLabelFontSize: 10, valGridLine: { color: 'E1E6E8', size: 0.5 }, catGridLine: { style: 'none' as const }, dataLabelFontFace: font, dataLabelFontSize: 9,
    titleFontFace: font, titleFontSize: 13, titleColor: C.ink, legendFontFace: font, legendFontSize: 10 };
  let n = 1;

  // 1 cover
  let s = pptx.addSlide();
  s.background = { color: C.deep };
  s.addText(lbl('bp.title'), { x: 0.8, y: 2.3, w: 11.5, h: 1.0, fontFace: font, fontSize: 40, bold: true, color: 'FFFFFF', align });
  s.addText(L(b.entity.name_en, b.entity.name_ar), { x: 0.8, y: 3.3, w: 11.5, h: 0.6, fontFace: font, fontSize: 22, color: 'DCE8EB', align });
  s.addText(`${lbl('bp.as_of')} ${e.as_of.split('-').reverse().join('/')} · ${lbl('rp.generated')} ${stamp(b.generated_at)} · ${b.generated_by ?? ''}`,
    { x: 0.8, y: 4.1, w: 11.5, h: 0.4, fontFace: font, fontSize: 13, color: C.brass, align });
  s.addText(lbl('rp.confidential'), { x: 0.8, y: 6.6, w: 11.5, h: 0.4, fontFace: font, fontSize: 11, color: 'DCE8EB', align });

  // 2 key figures
  s = pptx.addSlide(); n++;
  titleSlide(s, lbl('bp.kpis'), lbl('bp.kpis_sub'));
  const kpis: [string, string, string][] = [
    [lbl('bp.headcount'), String(e.snapshot.headcount), `${lbl('bp.female')} ${e.snapshot.female} · ${lbl('bp.probation')} ${e.snapshot.probation}`],
    [lbl('bp.omani_pct'), pct(last?.omani_pct), `${e.snapshot.omani} / ${e.snapshot.headcount}`],
    [lbl('bp.turnover'), pct(turnover), lbl('bp.last12')],
    [lbl('bp.absence'), pct(absence), lbl('bp.last12')],
    [lbl('bp.payroll_cost'), e.show_pay ? money(lastPay?.payroll_cost ?? null) : '—', `OMR · ${lastPay?.month ?? last?.month ?? ''}`],
    [lbl('bp.gratuity'), e.show_pay ? money(e.risks.gratuity_liability) : '—', 'OMR'],
    [lbl('bp.tenure'), e.snapshot.avg_tenure_years == null ? '—' : String(e.snapshot.avg_tenure_years), lbl('bp.years')],
    [lbl('bp.avg_age'), e.snapshot.avg_age == null ? '—' : String(e.snapshot.avg_age), lbl('bp.years')],
  ];
  kpis.forEach(([k, v, sub], i) => {
    const x = 0.5 + (i % 4) * 3.1, y = 1.7 + Math.floor(i / 4) * 2.55;
    s.addShape(pptx.ShapeType.roundRect, { x, y, w: 2.9, h: 2.3, fill: { color: C.page }, line: { color: C.page }, rectRadius: 0.08 });
    s.addText(k, { x: x + 0.2, y: y + 0.2, w: 2.5, h: 0.45, fontFace: font, fontSize: 13, color: C.muted, align });
    s.addText(v, { x: x + 0.2, y: y + 0.7, w: 2.5, h: 0.9, fontFace: font, fontSize: 34, bold: true, color: C.petrol, align });
    s.addText(sub, { x: x + 0.2, y: y + 1.65, w: 2.5, h: 0.45, fontFace: font, fontSize: 11, color: C.ink, align });
  });
  footer(s, n);

  // 3 headcount trend
  s = pptx.addSlide(); n++;
  titleSlide(s, lbl('bp.hc_trend'), lbl('bp.last12'));
  s.addChart(pptx.ChartType.line, [{ name: lbl('bp.headcount'), labels: months, values: e.months.map((m) => m.headcount) }],
    { x: 0.5, y: 1.6, w: 12.3, h: 5.2, ...chartBase, chartColors: [C.petrol], lineSize: 3, lineDataSymbolSize: 7, showValue: true, dataLabelPosition: 't',
      showLegend: false, valAxisMinVal: 0 });
  footer(s, n);

  // 4 joiners and leavers
  s = pptx.addSlide(); n++;
  titleSlide(s, lbl('bp.movement'), lbl('bp.last12'));
  s.addChart(pptx.ChartType.bar, [{ name: lbl('bp.joiners'), labels: months, values: e.months.map((m) => m.joiners) },
    { name: lbl('bp.leavers'), labels: months, values: e.months.map((m) => m.leavers) }],
    { x: 0.5, y: 1.6, w: 12.3, h: 5.2, ...chartBase, barDir: 'col', barGrouping: 'clustered', chartColors: [C.petrol, C.brass], showValue: true,
      dataLabelPosition: 'outEnd', showLegend: true, legendPos: 'b' });
  footer(s, n);

  // 5 Omanisation
  s = pptx.addSlide(); n++;
  titleSlide(s, lbl('bp.omanisation'), lbl('bp.omanisation_sub'));
  s.addChart(pptx.ChartType.line, [{ name: lbl('bp.omani_pct'), labels: months, values: e.months.map((m) => m.omani_pct ?? 0) }],
    { x: 0.5, y: 1.6, w: e.by_department.length ? 5.9 : 12.3, h: 5.2, ...chartBase, chartColors: [C.green], lineSize: 3, showValue: true, dataLabelPosition: 't', showLegend: false,
      valAxisMinVal: 0, showTitle: true, title: lbl('bp.omani_trend') });
  const deps = e.by_department.slice(0, 12);
  if (deps.length) {
    s.addChart(pptx.ChartType.bar, [{ name: lbl('bp.omani_pct'), labels: deps.map((d) => L(d.name_en, d.name_ar)),
      values: deps.map((d) => (d.total ? Math.round((1000 * d.omani) / d.total) / 10 : 0)) }],
      { x: 6.9, y: 1.6, w: 5.9, h: 5.2, ...chartBase, barDir: 'bar', chartColors: [C.petrol], showValue: true, dataLabelPosition: 'outEnd', showLegend: false,
        valAxisMinVal: 0, valAxisMaxVal: 100, showTitle: true, title: lbl('bp.omani_by_dept') });
  }
  footer(s, n);

  // 6 workforce mix
  s = pptx.addSlide(); n++;
  titleSlide(s, lbl('bp.mix'));
  if (deps.length) s.addChart(pptx.ChartType.bar, [{ name: lbl('bp.headcount'), labels: deps.map((d) => L(d.name_en, d.name_ar)), values: deps.map((d) => d.total) }],
    { x: 0.5, y: 1.3, w: 5.9, h: 5.5, ...chartBase, barDir: 'bar', chartColors: [C.petrol], showValue: true, dataLabelPosition: 'outEnd', showLegend: false,
      showTitle: true, title: lbl('bp.by_dept') });
  const nats = e.by_nationality.slice(0, 10);
  if (nats.length) s.addChart(pptx.ChartType.doughnut, [{ name: lbl('bp.headcount'), labels: nats.map((x) => L(x.name_en ?? x.code, x.name_ar)), values: nats.map((x) => x.total) }],
    { x: deps.length ? 6.9 : 0.5, y: 1.3, w: deps.length ? 5.9 : 12.3, h: 5.5, ...chartBase, holeSize: 55, showPercent: true, showValue: false, showLegend: true, legendPos: 'r',
      chartColors: [C.petrol, C.brass, C.green, '5B7C86', '8FB3BC', 'B4442F', '2D4A53', 'D8C38A', '6FA287', 'A9B8BD'], showTitle: true, title: lbl('bp.by_nat') });
  footer(s, n);

  // 7 payroll cost
  if (e.show_pay) {
    s = pptx.addSlide(); n++;
    titleSlide(s, lbl('bp.payroll'), lbl('bp.payroll_sub'));
    s.addChart(pptx.ChartType.bar, [{ name: lbl('bp.payroll_cost'), labels: months, values: e.months.map((m) => Math.round(m.payroll_cost ?? 0)) }],
      { x: 0.5, y: 1.6, w: (b.payroll_by_department ?? []).length ? 6.6 : 12.3, h: 5.2, ...chartBase, barDir: 'col', chartColors: [C.petrol], showValue: true, dataLabelPosition: 'outEnd', dataLabelFormatCode: '#,##0',
        valAxisLabelFormatCode: '#,##0', showLegend: false, showTitle: true, title: lbl('bp.cost_trend') });
    const pd = (b.payroll_by_department ?? []).slice(0, 10);
    if (pd.length) {
      s.addTable([[{ text: lbl('bp.department'), options: { bold: true, color: 'FFFFFF', fill: { color: C.petrol } } },
        { text: lbl('bp.employees'), options: { bold: true, color: 'FFFFFF', fill: { color: C.petrol }, align: 'right' } },
        { text: `${lbl('bp.cost')} (OMR)`, options: { bold: true, color: 'FFFFFF', fill: { color: C.petrol }, align: 'right' } }],
        ...pd.map((d) => [{ text: L(d.name_en, d.name_ar) }, { text: String(d.headcount), options: { align: 'right' as const } }, { text: money(d.cost), options: { align: 'right' as const } }])],
        { x: 7.4, y: 1.6, w: 5.4, colW: [2.8, 1.1, 1.5], fontFace: font, fontSize: 11, color: C.ink, border: { type: 'solid', pt: 0.5, color: 'D5DDE0' }, rowH: 0.36 });
      s.addText(`${lbl('bp.payroll_month')} ${b.payroll_month ?? ''}`, { x: 7.4, y: 6.4, w: 5.4, h: 0.3, fontFace: font, fontSize: 10, color: C.muted, align });
    }
    footer(s, n);
  }

  // 8 time
  s = pptx.addSlide(); n++;
  titleSlide(s, lbl('bp.time'), lbl('bp.last12'));
  s.addChart(pptx.ChartType.bar, [{ name: lbl('bp.overtime'), labels: months, values: e.months.map((m) => m.overtime_hours) }],
    { x: 0.5, y: 1.6, w: 5.9, h: 5.2, ...chartBase, barDir: 'col', chartColors: [C.brass], showValue: true, dataLabelPosition: 'outEnd', showLegend: false,
      showTitle: true, title: lbl('bp.overtime') });
  s.addChart(pptx.ChartType.line, [{ name: lbl('bp.absence'), labels: months, values: e.months.map((m) => (m.worked_days ? Math.round((1000 * m.absent_days) / m.worked_days) / 10 : 0)) }],
    { x: 6.9, y: 1.6, w: 5.9, h: 5.2, ...chartBase, chartColors: [C.red], lineSize: 3, showValue: true, dataLabelPosition: 't', showLegend: false, valAxisMinVal: 0,
      showTitle: true, title: `${lbl('bp.absence')} (%)` });
  footer(s, n);

  // 9 risks and compliance
  s = pptx.addSlide(); n++;
  titleSlide(s, lbl('bp.risks'));
  const risks: [string, number | string, boolean][] = [
    [lbl('bp.docs_expired'), e.risks.documents_expired, e.risks.documents_expired > 0], [lbl('bp.docs_30'), e.risks.documents_30, e.risks.documents_30 > 0],
    [lbl('bp.open_positions'), e.risks.open_positions, false], [lbl('bp.injuries'), `${e.risks.injuries_ytd} · ${e.risks.lost_days_ytd} ${lbl('bp.lost_days')}`, e.risks.injuries_ytd > 0],
    [lbl('bp.open_cases'), e.risks.open_cases, false], [lbl('bp.exits_open'), e.risks.exits_open, false],
  ];
  risks.forEach(([k, v, bad], i) => {
    const y = 1.4 + i * 0.62;
    const rw = b.expiries_by_type.length ? 5.9 : 12.3;
    s.addShape(pptx.ShapeType.roundRect, { x: 0.5, y, w: rw, h: 0.52, fill: { color: i % 2 ? 'FFFFFF' : C.page }, line: { color: C.page }, rectRadius: 0.05 });
    s.addText(k, { x: 0.7, y, w: rw - 2.6, h: 0.52, fontFace: font, fontSize: 13, color: C.ink, align, valign: 'middle' });
    s.addText(String(v), { x: rw - 1.9, y, w: 2.2, h: 0.52, fontFace: font, fontSize: 15, bold: true, color: bad ? C.red : C.petrol, align: 'right', valign: 'middle' });
  });
  const ex = b.expiries_by_type.slice(0, 9);
  if (ex.length) {
    s.addTable([[{ text: lbl('bp.document'), options: { bold: true, color: 'FFFFFF', fill: { color: C.petrol } } },
      { text: lbl('bp.expired'), options: { bold: true, color: 'FFFFFF', fill: { color: C.petrol }, align: 'right' } },
      { text: '0–30', options: { bold: true, color: 'FFFFFF', fill: { color: C.petrol }, align: 'right' } },
      { text: '31–90', options: { bold: true, color: 'FFFFFF', fill: { color: C.petrol }, align: 'right' } }],
      ...ex.map((x) => [{ text: L(x.name_en, x.name_ar) }, { text: String(x.expired), options: { align: 'right' as const, color: x.expired ? C.red : C.ink, bold: x.expired > 0 } },
        { text: String(x.d30), options: { align: 'right' as const } }, { text: String(x.d90), options: { align: 'right' as const } }])],
      { x: 6.9, y: 1.4, w: 5.9, colW: [3.2, 0.9, 0.9, 0.9], fontFace: font, fontSize: 11, color: C.ink, border: { type: 'solid', pt: 0.5, color: 'D5DDE0' }, rowH: 0.36 });
  }
  footer(s, n);

  // 10 leavers by reason
  if (b.leavers_by_type.length) {
    s = pptx.addSlide(); n++;
    titleSlide(s, lbl('bp.leavers_reason'), lbl('bp.last12'));
    s.addChart(pptx.ChartType.bar, [{ name: lbl('bp.leavers'), labels: b.leavers_by_type.map((x) => codeLabel(x.type, lang)), values: b.leavers_by_type.map((x) => x.n) }],
      { x: 0.5, y: 1.6, w: 12.3, h: 5.2, ...chartBase, barDir: 'bar', chartColors: [C.brass], showValue: true, dataLabelPosition: 'outEnd', showLegend: false });
    footer(s, n);
  }

  const blob = (await pptx.write({ outputType: 'blob' })) as Blob;
  const month = e.as_of.slice(0, 7);
  await saveFile(`${b.entity.code}_Board-pack_${month}.pptx`, blob);
}
