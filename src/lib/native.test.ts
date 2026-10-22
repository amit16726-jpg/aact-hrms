import { describe, expect, it } from 'vitest';
import { canPrint, isNative, safeFileName } from './native';

describe('native helpers', () => {
  it('is not native in a browser (tests run in jsdom)', () => {
    expect(isNative()).toBe(false);
    expect(canPrint()).toBe(true);
  });
  it('makes file names safe', () => {
    expect(safeFileName('SIF_123/BANK:2026*.csv')).toBe('SIF_123_BANK_2026_.csv');
    expect(safeFileName('   ')).toBe('export');
    expect(safeFileName('كشف الرواتب.csv')).toBe('كشف الرواتب.csv');
  });
});
