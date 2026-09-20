/**
 * Bounded ring buffer (EPIC E-047-3_7, Step 1).
 *
 * Canonical, dependency-free fixed-size circular buffer providing O(1)
 * insertion and O(n) ordered retrieval. When full, the oldest entry is
 * overwritten (oldest-first eviction).
 *
 * This is the SINGLE source of truth for the ring buffer used across the
 * server. Phase 2 (E-047-2_7 Step 7) had a local copy inside
 * `services/scanner-cache.ts`; that copy now re-exports from here so there is
 * exactly one implementation.
 *
 * Salvaged from `packages/aid-gui/server/watchers/stage-log-stream.ts`
 * (the `CircularBuffer` class) and adapted to NodeNext.
 */

/**
 * Fixed-size circular buffer providing O(1) insertion and O(n) ordered
 * retrieval. When full, the oldest entry is overwritten.
 */
export class CircularBuffer<T> {
  private readonly items: (T | undefined)[];
  private head = 0;
  private count = 0;
  private readonly capacity: number;

  /**
   * @param capacity - maximum number of retained items (default 500). Must be
   *   >= 1; a smaller value throws.
   */
  constructor(capacity = 500) {
    if (capacity < 1) {
      throw new Error(`CircularBuffer capacity must be >= 1, got ${capacity}`);
    }
    this.capacity = capacity;
    this.items = new Array<T | undefined>(capacity).fill(undefined);
  }

  /** Add an item to the buffer. Overwrites the oldest entry when full. */
  push(item: T): void {
    this.items[this.head] = item;
    this.head = (this.head + 1) % this.capacity;
    if (this.count < this.capacity) {
      this.count++;
    }
  }

  /** Return all buffered items in insertion order (oldest first). */
  toArray(): T[] {
    if (this.count === 0) return [];

    const result: T[] = [];
    // When the buffer is not yet full, items start at index 0. When full, the
    // oldest item is at `head` (where the next write will go).
    const start = this.count < this.capacity ? 0 : this.head;
    for (let i = 0; i < this.count; i++) {
      const idx = (start + i) % this.capacity;
      result.push(this.items[idx] as T);
    }
    return result;
  }

  /** Clear all entries from the buffer. */
  clear(): void {
    this.items.fill(undefined);
    this.head = 0;
    this.count = 0;
  }

  /** Current number of items in the buffer. */
  get size(): number {
    return this.count;
  }

  /** Configured maximum number of items. */
  get max(): number {
    return this.capacity;
  }
}
