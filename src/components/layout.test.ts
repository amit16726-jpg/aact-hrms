import { describe, expect, it } from 'vitest';
import { initials } from './Layout';

describe('initials', () => {
  it('takes the first and last word', () => { expect(initials('Maryam Al Hinai')).toBe('MH'); });
  it('handles one word and e-mail addresses', () => {
    expect(initials('Ravi')).toBe('R');
    expect(initials('hr.manager@aact.om')).toBe('HM');
  });
  it('never returns an empty string', () => { expect(initials('')).toBe('?'); expect(initials(null)).toBe('?'); });
});
