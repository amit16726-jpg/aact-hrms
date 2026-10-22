import { describe, expect, it } from 'vitest';
import { secondsLeft } from './idle';
import { codeOk } from './mfa';

describe('automatic sign-out and code checks', () => {
  it('counts down from the last activity', () => {
    const t0 = 1_000_000;
    expect(secondsLeft(t0, t0, 30)).toBe(1800);
    expect(secondsLeft(t0, t0 + 29 * 60_000, 30)).toBe(60);
    expect(secondsLeft(t0, t0 + 31 * 60_000, 30)).toBe(0);
  });
  it('accepts six digits with spaces only', () => {
    expect(codeOk('123 456')).toBe(true);
    expect(codeOk('12345')).toBe(false);
    expect(codeOk('12345a')).toBe(false);
  });
});
