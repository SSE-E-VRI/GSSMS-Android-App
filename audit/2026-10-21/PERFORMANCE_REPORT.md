# Performance and reliability

Status: BLOCKED for Android measurements; no connected device/emulator. No startup, frame-time, memory, CPU, battery, bandwidth or ANR measurements collected. Host unit-test duration is not Android performance evidence.

Source observations: large cached lists use compute beyond 200 rows/100KB decode; evidence processing uses compute, 30MB input byte cap and 1600px normalization; bounded pagination limits requests; profile photo response size checked after buffering, so its 5MB acceptance cap does not bound download memory. Image pixel counts, many evidence previews, PDF generation and long-running offline usage require profiling.

Proposed acceptance budgets for product approval (not established project requirements): representative low-end supported phone cold startup p95 <=3s, warm <=1s; no ANR/crash in 60-minute route/queue soak; no persistent heap growth after repeated navigation/GC; rendering frames assessed at device refresh budget (16.7ms at 60Hz); API responsiveness measured independently under controlled network. Record device, OS, build mode, sample count, warmup, trace and p50/p95 before evaluating.

Plan: profile cold/warm start, large work-order/asset lists, checklist scroll/photo capture, multi-page PDF, 1,000 queued commands, network flapping, foreground/background cycles, low memory and kill/restart. Use Flutter DevTools/Android profiling and add Macrobenchmark/Baseline Profiles only if supported and approved. No production artifact generated to obtain these measurements.
