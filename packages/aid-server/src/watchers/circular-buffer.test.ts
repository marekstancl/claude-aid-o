/**
 * CircularBuffer test suite (EPIC E-047-3_7, Step 1).
 *
 * AC5: capacity cap, oldest-first eviction, toArray order, capacity>=1 guard.
 */

import { describe, expect, it } from 'vitest';
import { CircularBuffer } from './circular-buffer.js';

describe('CircularBuffer', () => {
  it('rejects capacity < 1 (guard)', () => {
    expect(() => new CircularBuffer<number>(0)).toThrow(/capacity must be >= 1/);
    expect(() => new CircularBuffer<number>(-3)).toThrow(/capacity must be >= 1/);
  });

  it('defaults to capacity 500', () => {
    const b = new CircularBuffer<number>();
    expect(b.max).toBe(500);
  });

  it('accepts capacity 1 (boundary) and keeps only the newest', () => {
    const b = new CircularBuffer<number>(1);
    b.push(10);
    b.push(20);
    expect(b.toArray()).toEqual([20]);
    expect(b.size).toBe(1);
    expect(b.max).toBe(1);
  });

  it('preserves insertion order before wrap', () => {
    const b = new CircularBuffer<number>(5);
    b.push(1);
    b.push(2);
    b.push(3);
    expect(b.toArray()).toEqual([1, 2, 3]);
    expect(b.size).toBe(3);
  });

  it('caps at capacity and evicts oldest-first when full', () => {
    const b = new CircularBuffer<number>(3);
    [1, 2, 3, 4, 5].forEach((n) => b.push(n));
    expect(b.toArray()).toEqual([3, 4, 5]); // 1 and 2 evicted, order preserved
    expect(b.size).toBe(3);
  });

  it('toArray returns oldest-first order across a wrap boundary', () => {
    const b = new CircularBuffer<string>(3);
    ['a', 'b', 'c'].forEach((x) => b.push(x));
    b.push('d'); // evicts 'a'
    expect(b.toArray()).toEqual(['b', 'c', 'd']);
    b.push('e'); // evicts 'b'
    expect(b.toArray()).toEqual(['c', 'd', 'e']);
  });

  it('clear() resets to empty', () => {
    const b = new CircularBuffer<number>(3);
    b.push(1);
    b.push(2);
    b.clear();
    expect(b.toArray()).toEqual([]);
    expect(b.size).toBe(0);
  });

  it('toArray on an empty buffer is []', () => {
    const b = new CircularBuffer<number>(4);
    expect(b.toArray()).toEqual([]);
  });
});
