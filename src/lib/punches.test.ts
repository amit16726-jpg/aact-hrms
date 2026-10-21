import { describe, expect, it } from 'vitest';
import { buildPunches, detectDelimiter, guessMap, parseCsv, parseDate, parseDateTime, parseDirection, parseTime } from './punches';
import { addMonths, daysInclusive, fmtDuration, monthDays } from './format';

describe('punch file reading', () => {
  it('detects delimiters and parses quoted CSV with BOM and CRLF', () => {
    expect(detectDelimiter('a;b;c\n1;2;3')).toBe(';');
    expect(detectDelimiter('a\tb\n1\t2')).toBe('\t');
    expect(parseCsv('﻿no,name,time\r\n"001","Kumar, Ravi",07:05\r\n\r\n002,"Say ""hi""",08:00')).toEqual([
      ['no', 'name', 'time'], ['001', 'Kumar, Ravi', '07:05'], ['002', 'Say "hi"', '08:00']]);
  });
  it('reads dates in the chosen order and rejects impossible ones', () => {
    expect(parseDate('20/10/2026', 'DMY')).toBe('2026-10-20');
    expect(parseDate('10/20/2026', 'MDY')).toBe('2026-10-20');
    expect(parseDate('2026-10-20', 'DMY')).toBe('2026-10-20');
    expect(parseDate('20.10.26', 'DMY')).toBe('2026-10-20');
    expect(parseDate('31/02/2026', 'DMY')).toBeNull();
    expect(parseDate('hello', 'DMY')).toBeNull();
  });
  it('reads 24-hour and AM/PM times', () => {
    expect(parseTime('7:05')).toBe('07:05:00');
    expect(parseTime('19:05:30')).toBe('19:05:30');
    expect(parseTime('7:05 PM')).toBe('19:05:00');
    expect(parseTime('12:10 am')).toBe('00:10:00');
    expect(parseTime('25:00')).toBeNull();
    expect(parseDateTime('2026-10-20T07:05:00', 'DMY')).toBe('2026-10-20 07:05:00');
    expect(parseDateTime('20/10/2026 7:05 PM', 'DMY')).toBe('2026-10-20 19:05:00');
  });
  it('maps direction words and device codes', () => {
    expect(parseDirection('Check In')).toBe('IN');
    expect(parseDirection('C/Out')).toBe('OUT');
    expect(parseDirection('0')).toBe('IN');
    expect(parseDirection('')).toBeNull();
  });
  it('builds punches from separate or combined columns and reports bad lines', () => {
    const rows = parseCsv('AC-No.,Date,Time,State\n1001,20/10/2026,06:58,C/In\n1001,20/10/2026,16:05,C/Out\n,20/10/2026,07:00,\n1002,99/99/2026,07:00,');
    const map = { ...guessMap(rows[0]), fmt: 'DMY' as const, header: true };
    expect(map.ref).toBe(0);
    expect(map.date).toBe(1);
    expect(map.time).toBe(2);
    expect(map.dir).toBe(3);
    const r = buildPunches(rows, { ref: map.ref!, datetime: map.datetime ?? null, date: map.date ?? null, time: map.time ?? null, dir: map.dir ?? null, fmt: 'DMY', header: true });
    expect(r.ok).toEqual([
      { line: 2, ref: '1001', at: '2026-10-20 06:58:00', dir: 'IN' },
      { line: 3, ref: '1001', at: '2026-10-20 16:05:00', dir: 'OUT' }]);
    expect(r.bad).toEqual([{ line: 4, problem: 'ref' }, { line: 5, problem: 'date' }]);
    const combined = buildPunches([['AACT-00017', '2026-10-20 07:01']], { ref: 0, datetime: 1, date: null, time: null, dir: null, fmt: 'DMY', header: false });
    expect(combined.ok[0].at).toBe('2026-10-20 07:01:00');
  });
});

describe('time formatting', () => {
  it('formats durations and months', () => {
    expect(fmtDuration(485)).toBe('8:05');
    expect(fmtDuration(0)).toBe('—');
    expect(addMonths('2026-12', 1)).toBe('2027-01');
    expect(addMonths('2026-01', -1)).toBe('2025-12');
    const days = monthDays('2026-10');
    expect(days).toHaveLength(31);
    expect(days[19]).toEqual({ day: 20, iso: '2026-10-20', dow: 2 });
    expect(daysInclusive('2026-10-20', '2026-10-24')).toBe(5);
  });
});
