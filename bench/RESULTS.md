# sNotate: benchmark results

One line per run of `make bench` (SN-606). Targets: open a 30-step case to the storyboard under 500 ms, tool response under one frame at 120 Hz (8.3 ms: main-thread time per drag event including the commit, events paced at 120 Hz), export of 30 annotated steps under 5 s.

- 2026-10-27 be95a94 Mac16,8: launch to first paint 110.1 ms, to storyboard frames 190.2 ms (median of 5); drag frame median/max after the first 2.4/9.5 ms at 1600x1000, 3.3/6.3 ms at 8192x8192, first frame of a gesture 9.4/6.3 ms, 8k first frame 146.6 ms; export of 30 steps 0.58 s
