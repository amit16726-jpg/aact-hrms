import { describe, expect, it } from 'vitest';
import { splitAliases } from './aliases';

describe('splitAliases', () => {
  it('splits on commas and Arabic commas, trims and removes duplicates', () => {
    expect(splitAliases('Lab, Plant  1،Maint , lab,,')).toEqual(['Lab', 'Plant 1', 'Maint']);
  });
  it('accepts an array and empty values', () => {
    expect(splitAliases([' GP ', 'Glaze'])).toEqual(['GP', 'Glaze']);
    expect(splitAliases('')).toEqual([]);
    expect(splitAliases(null)).toEqual([]);
  });
});
