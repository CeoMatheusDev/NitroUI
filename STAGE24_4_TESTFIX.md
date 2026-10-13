# Stage 24.4 — Test correction

Corrected the capacity precondition in `stage24 widget failure rolls back interaction and geometry`. After a failed checkbox, rollback restores one rectangle (4 vertices / 6 indices), leaving enough capacity for a button. The test now fills the remaining capacity before expecting the button to fail. This changes only the test, not the widget implementation or public API.

Validation: static review only; Zig 0.17.0 compiler was not available in this environment.
