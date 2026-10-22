import { describe, expect, it } from 'vitest';
import { installMode, isIos } from './install';

describe('install helpers', () => {
  it('recognises iPhone, iPad and iPadOS desktop mode', () => {
    expect(isIos('Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)', 5)).toBe(true);
    expect(isIos('Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X)', 5)).toBe(true);
    expect(isIos('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)', 5)).toBe(true);
    expect(isIos('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)', 0)).toBe(false);
    expect(isIos('Mozilla/5.0 (Linux; Android 14; Pixel 8)', 5)).toBe(false);
  });
  it('offers nothing on a desktop browser without an install prompt', () => {
    expect(installMode()).toBe(null);
  });
});
