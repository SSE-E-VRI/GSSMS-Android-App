# UI/UX Design Review — Audit Checklist & Recommendations

> **Scope note:** This is a general-purpose UI/UX audit framework. For a review tailored to your specific product, share the app URL, screenshots, or a screen recording and each section below can be filled in with concrete, product-specific findings.

---

## How to Use This Document

1. Go through each section with your product open in front of you.
2. Rate each item: ✅ Pass / ⚠️ Needs work / ❌ Fail / ➖ N/A
3. Prioritize fixes using the **Impact vs. Effort** guidance at the end.
4. Re-audit quarterly — UI/UX debt accumulates fast.

---

## 1. First Impressions (5-second test)

| Check | Rating | Notes |
|---|---|---|
| Can a first-time visitor tell *what the product does* within 5 seconds? | | |
| Is there one clear primary action above the fold? | | |
| Does the page look trustworthy (no typos, no broken images, no placeholder text)? | | |
| Is visual hierarchy obvious — headline > subtext > CTA? | | |

**Common fixes:**
- Rewrite the hero headline to state the *outcome* for the user, not the feature ("Ship invoices faster" not "Automated invoicing platform").
- Ensure exactly one visually dominant CTA per view. Secondary actions should be visually quiet (ghost buttons, text links).

---

## 2. Navigation & Information Architecture

- [ ] Navigation is consistent across all pages/views (same position, same labels)
- [ ] No more than ~7 top-level items; deeper items are grouped logically
- [ ] Users can always answer: *Where am I? How did I get here? Where can I go?*
- [ ] Breadcrumbs or a visible active-state on navigation items
- [ ] Labels use the user's vocabulary, not internal jargon
- [ ] Search exists (if content exceeds ~30 items) and returns useful, ranked results
- [ ] Mobile navigation is reachable with one thumb; no hover-only interactions

**Red flags:** menu items that only make sense to the team, dead-end pages, "mystery meat" icons without labels or tooltips.

---

## 3. Visual Design & Consistency

- [ ] **Typography:** max 2 font families; a clear type scale (e.g., 12 / 14 / 16 / 20 / 24 / 32); line height ≥ 1.4 for body text
- [ ] **Color:** a defined palette used consistently; one primary action color; color is never the *only* carrier of meaning (accessibility)
- [ ] **Spacing:** spacing follows a system (4/8pt grid), not arbitrary pixel values
- [ ] **Components:** buttons, inputs, cards, and modals look and behave identically everywhere
- [ ] **Iconography:** one icon set, consistent stroke weight; icons paired with text for anything non-obvious
- [ ] **Use of a design system or component library** (even a lightweight one) rather than one-off styling

**Quick test:** Screenshot 5 different screens and lay them side by side. If they look like different products, consistency is the problem.

---

## 4. Accessibility (a11y) — Non-negotiable

- [ ] Contrast ratio ≥ 4.5:1 for body text, ≥ 3:1 for large text (WCAG AA)
- [ ] All interactive elements keyboard-navigable with a visible focus state
- [ ] Proper semantic HTML (real `<button>`, `<label>` tied to inputs, heading hierarchy h1→h6 without skips)
- [ ] Alt text on meaningful images; decorative images hidden from screen readers
- [ ] Forms: labels (not placeholder-as-label), inline error messages, `aria-describedby` for hints
- [ ] No content that flashes > 3 times per second
- [ ] Works at 200% zoom without breaking layouts
- [ ] Tested with a screen reader (VoiceOver / NVDA) at least once

**Tooling:** run Lighthouse and axe DevTools; both catch the majority of issues in minutes.

---

## 5. Forms & Input

- [ ] Ask only for what's strictly necessary — every extra field measurably lowers completion
- [ ] Labels sit above inputs (not inside as placeholders that disappear)
- [ ] Appropriate input types on mobile (`type="email"` triggers the right keyboard)
- [ ] Inline validation *after* blur or submit — not per-keystroke aggression
- [ ] Error messages say **how to fix it** ("Phone number must be 10 digits"), not just what's wrong
- [ ] Long forms are broken into steps with progress indication
- [ ] Autocomplete attributes set; password managers work

**Rule of thumb:** every field should justify its existence against a ~7% drop in completion per unnecessary field.

---

## 6. Feedback & System Status

- [ ] Every action gives feedback within 100ms (optimistic UI or loading state)
- [ ] Loading states are skeletons or spinners — never a blank screen
- [ ] Success actions are confirmed (toast, checkmark, state change)
- [ ] Destructive actions have confirmation or undo (prefer **undo over confirm** where possible)
- [ ] Empty states tell the user what to do next, with a CTA — not just "No data"
- [ ] Errors are human, specific, and actionable

---

## 7. Performance Perception

- [ ] Largest Contentful Paint < 2.5s on 4G mobile (check PageSpeed Insights)
- [ ] Interactions feel instant (< 100ms response)
- [ ] Images optimized (WebP/AVIF, lazy-loaded, correct dimensions to prevent layout shift)
- [ ] Fonts: `font-display: swap`, subset, ≤ 2 weights if possible
- [ ] No layout shift as content loads (reserve space for images/ads)

Remember: **perceived** performance matters as much as actual. Skeleton screens and instant acknowledgments make a slow backend feel fast.

---

## 8. Mobile & Responsive

- [ ] Designed mobile-first or at least verified at 360px width
- [ ] Touch targets ≥ 44×44px with adequate spacing (no fat-finger errors)
- [ ] No horizontal scrolling or zoom-to-read text (base font ≥ 16px prevents iOS auto-zoom)
- [ ] Sticky elements (headers, CTAs) don't cover content or inputs when the keyboard opens
- [ ] Tested on real devices, not just browser devtools

---

## 9. Microcopy & Content

- [ ] Buttons describe the action: "Save changes" not "Submit"; "Create account" not "Sign up now!"
- [ ] No lorem ipsum, no "Error 500" — plain language that says what happened and what to do
- [ ] Tone is consistent (define it: formal / friendly / playful) across all surfaces
- [ ] Numbers, dates, and names formatted correctly for the locale
- [ ] Onboarding copy explains *why* each step exists

---

## 10. User Flows & Conversion

Audit your 2–3 most important flows end-to-end (signup, core action, checkout/settings):

- [ ] Number of steps minimized — each screen asks one thing
- [ ] Progress is visible in multi-step flows
- [ ] Users can go back without losing data
- [ ] Friction removed from the happy path; advanced options deferred or tucked away
- [ ] Drop-off points measured (funnel analytics) — fix the biggest leak first

**Method:** run a 5-user moderated usability test. Nielsen's research shows 5 users surface ~85% of usability problems.

---

## Prioritization Framework

Plot findings on a 2×2:

|  | Low Effort | High Effort |
|---|---|---|
| **High Impact** | 🚀 Do this week | 📅 Plan this quarter |
| **Low Impact** | 🧹 Batch into polish sprints | ❄️ Skip / icebox |

**Typical quick wins:** contrast fixes, placeholder-as-label fixes, button copy rewrites, empty states, focus states, hero headline rewrite.

---

## Suggested Audit Workflow

1. **Heuristic pass** — walk this checklist (1–2 hours)
2. **Automated scan** — Lighthouse + axe + PageSpeed (30 min)
3. **5-user usability test** — watch where people hesitate (1 day)
4. **Analytics review** — find the funnel's biggest drop-off (1 hour)
5. **Prioritize & ship** — quick wins first, systemic issues into the roadmap

---

*Generated as a general-purpose audit. Share your product's URL or screenshots for a review with specific, prioritized findings.*
