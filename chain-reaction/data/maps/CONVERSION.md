# Unity map conversion

Generated from `tools/unity_import/`. Out-of-bounds atoms are dropped. Duplicate cells keep the last write.

## campaign

- 1-5: duplicate cell (3,0), last write wins

## custom

- relay-race: dropped out-of-bounds atom (2,3)

## Phase D

- relay-race: deleting `(2,3)` left catching with no NE/SE feeder on `height=3`. Raised `height` to 4 so the original cell is legal and restored the movable (`NE`, `SE`). After setup: 9 atoms at `(0,1)`, `(3,0)`, `(3,2)`, `(3,1)`, `(1,0)`, `(1,1)`, `(1,2)`, `(2,0)`, `(2,3)`. Steps stay 2. Headless checks load, drag, and catching; no automatic win asserted.

