# Front Door WAF — Residual assessment (post-May-12 rollout)

**Status:** draft for team review
**Window:** 2026-05-12 → 2026-05-26 (14 days, full post-rollout)
**Data:** `AzureDiagnostics` / `FrontDoorWebApplicationFirewallLog` on workspace `log-frontdoor-p-we-001` (`abcf8641-4b47-4e6a-a6cc-b29ddb6d0351`)
**Companion docs:** [`waf_triage_writeup.md`](./waf_triage_writeup.md) (the original assessment), [`waf_triage_kql_addendum.md`](./waf_triage_kql_addendum.md) (90-day KQL validation)

## TL;DR

The exclusion set deployed on May 12 is working: noise on every targeted selector dropped 89–99% versus the pre-rollout baseline. The custom probe-path rule landed in **Log** mode and catches ~50k events / 14d as expected.

Two things gate the Detection→Prevention flip:

1. **Four new FP selectors** surfaced at scale (none had visible volume in the original 15k CSV). All four are the same shape as existing exclusions and need to be added: `ep.click_url`/`ep.form_destination`/`ep.link_url` (GA4 enhanced ecommerce), `_csrfSecret` (next-auth), `ai_user`/`ai_session` (Application Insights), `__txn_*` cookies (new-shape DAS transaction cookies; **PII finding from the original writeup still applies — see §3**).
2. **CRS rules are still in `Log`** — the actual flip never happened. If we flipped today as-is, ~136k anomaly-scored requests over 14d would move from Log to Block, concentrated on `mijn`, `metrics`, and `adviseur`. With item 1 resolved that number drops materially.

`ProbePathLog` itself is ready to promote to Block — earlier draft of this writeup flagged a false alarm on `/auth/login`; the rule was matching `wp-*` content inside the `returnTo` query parameter (scanner open-redirect abuse), not the path. See §4.

## Action breakdown (14d, post-rollout)

| `action_s`       |  Events | Notes                                                |
| ---------------- | ------: | ---------------------------------------------------- |
| `Log`            | 879,530 | CRS rules + Bot300xxx + custom `ProbePathLog*`       |
| `AnomalyScoring` | 517,860 | post-evaluation rollup (rule 949110)                 |
| `Allow`          | 264,570 | GoodBots                                             |
| `Block`          |  40,735 | BadBots (30,827) + GeoBlocking (9,908) — **no CRS**  |

Block volume is up from ~96k / 90d to ~41k / 14d (≈3× rate), entirely from BadBots-Bot100200. No new custom block rule is enforcing — `ProbePathLog`/`ProbePathLog2` are deployed in **Log** action.

## 1. Exclusion set — working

Selector-level comparison for the rules the exclusions target. Pre-rollout rate is the 90-day count from the addendum normalised to a 14-day window.

| Rule   | Selector                  | Pre-rollout (14d-norm) |  Post-rollout 14d | Δ                |
| ------ | ------------------------- | ---------------------: | ----------------: | ---------------- |
| 942100 | `QueryParamValue:sst.us_privacy` |               ~180,400 |            15,925 | **−91%**         |
| 942100 | `CookieValue:CookieConsent`      |                  ~149 |                 — | **−100%**        |
| 942100 | `CookieValue:ttcsid` (family)    |                ~4,360 |              ~350 | **−92%**         |
| 931130 | `QueryParamValue:dl`             |               ~183,500 |            16,096 | **−91%**         |
| 931130 | `QueryParamValue:iss`            |                ~22,700 |             1,315 | **−94%**         |
| 931130 | `QueryParamValue:origin`         |                ~16,000 |             1,212 | **−92%**         |
| 931130 | `QueryParamValue:komtvan`        |                 ~7,970 |                 2 | **−99.97%**      |

The residual (1–16k) on the GA4-style selectors comes from the same parameters appearing on hosts the exclusion isn't scoped to. Two options: (a) broaden the scope (drop the host scope, since the params are GA-owned by name on every host), or (b) leave it — these are Log-only and don't contribute to enforcement. Recommend (a) for cleanliness.

## 2. New FP patterns — add exclusions

These surfaced at material volume in 14d and were not visible in the original CSV. All four match the shape of existing exclusions — opaque tokens or absolute URLs that the application stack never interpolates as SQL/HTML.

| Selector                                       | 14d events            | Rules tripped     | Provenance / fix                                                     |
| ---------------------------------------------- | --------------------: | ----------------- | --------------------------------------------------------------------- |
| `QueryParamValue:ep.click_url`                 |                 3,877 | 931130            | GA4 enhanced-measurement event params; same as `dl`. Add to exclusions. |
| `QueryParamValue:ep.form_destination`          |                 2,443 | 931130            | GA4 form-tracking. Same as above.                                       |
| `QueryParamValue:ep.link_url`                  |                   173 | 931130            | GA4 outbound-link. Same as above.                                       |
| `CookieValue:_csrfSecret`                      | 256 (942100) + 1,981 (941100) | 942100, 941100 | next-auth CSRF secret cookie (base64 + dot). Add `_csrfSecret` to RequestCookieNames. |
| `CookieValue:ai_user`, `CookieValue:ai_session`| ~3,400 (combined)     | 941100            | Application Insights JavaScript SDK cookies. Add both names.            |
| `CookieValue:__txn_*` (many random suffixes)   | ≥4,900 (4 cookies × 1,238 in top 8 alone) | 941100 | New shape of the DAS `transaction` cookie — random per-claim suffix. **§3.** |

Suggested change for `waf_triage.py` and the Bicep policy:

- **RequestCookieNames**: add `Equals: _csrfSecret`, `Equals: ai_user`, `Equals: ai_session`; add `StartsWith: __txn_`.
- **QueryStringArgNames**: add `StartsWith: ep.` (covers click_url / form_destination / link_url and any future GA4 enhanced-measurement params).

## 3. `__txn_*` cookies — PII concern, still unresolved

The original writeup flagged the `transaction` cookie on `www.das.nl` for carrying customer name + claim ID in plaintext. The cookie has since been refactored into a family of `__txn_<random>` cookies (likely one per active claim), but the payload shape is the same — same SQLI/XSS trip patterns, same dot-suffix base64 content. We can't read the payload from the WAF logs to confirm whether PII was removed in the rename, but the trip patterns match the historical shape.

**Recommendation:** before the exclusion ships, ask the web team to confirm the rename was paired with a payload change (server-side state under a session id, or JWE-encrypted client value). If the payload is still plaintext PII, the exclusion silences the WAF on a cookie that shouldn't carry that data in the first place — that's a worse end state than the noise.

## 4. `ProbePathLog` — ready to promote to Block

The custom probe-path rule is deployed in Log mode and catches the expected pattern set. Top 14d by request path:

| Path                             | Events |  IPs |
| -------------------------------- | -----: | ---: |
| `/wp-admin/index.php`            |  5,580 |   14 |
| `/AutoDiscover/autodiscover.xml` |  4,751 | 1,139 |
| `/xmlrpc.php`                    |  3,777 |   90 |
| `/auth/login`                    |  3,704 |  164 |
| `/wp-login.php`                  |  3,614 |  157 |
| `/console/login/LoginForm.jsp`   |    480 |    1 |
| `/.env`                          |    415 |  130 |
| `/manager/html`                  |    294 |    1 |

The `/auth/login` row looks alarming at first — that's a legitimate OIDC endpoint — but inspection of the match details shows the rule is matching `wp-*` content inside the `returnTo` query parameter, not the path:

```
URI matched: https://mijn.das.nl/auth/login?returnTo=/wp-content/plugins/wps-hide-login/wps-hide-login.php
URI matched: https://adviseurs.das.nl/auth/login?returnTo=/wp-content/plugins/hellopress/wp_filemanager.php
URI matched: https://adviseurs.das.nl/auth/login?returnTo=/wp-admin/css/bolt.php
```

This is scanner open-redirect abuse — 164 distinct IPs trying to bounce off `/auth/login` into WordPress probe paths. Legitimate OIDC flows never put `wp-*` into `returnTo`. The rule is working as intended on these too.

**Before promoting to Block, sanity-check with the auth team:**

- Does the app's `returnTo` validator already restrict to an allow-list (`*.das.nl` paths)? If yes, WAF-block is defense-in-depth and a clear win.
- If no, the WAF block is the only thing preventing the redirect — also fine, but flag the open-redirect risk separately for app-side fix.

The rest of the matched paths are unambiguous probes against stacks DAS does not run. **Recommendation: promote `ProbePathLog` and `ProbePathLog2` to Block.**

## 5. Bot300700 — still the dominant REVIEW pile

| Host                | Bot300700 (14d) | Pre-rollout 14d-norm | Δ                   |
| ------------------- | --------------: | -------------------: | ------------------- |
| `www.das.nl`        |         274,394 |                    — | (not separately sized before) |
| `mijn.das.nl`       |         133,071 |                    — | —                   |
| `assets.das.nl`     |          30,035 |              ~73,900 | **−59%**            |
| `adviseur.das.nl`   |          10,461 |                    — | —                   |
| 5 other auth hosts  |          ~18,700 |                    — | —                   |
| **Total**           |     **~468,700** |                    — | —                   |

`assets.das.nl` is down sharply (option D was either partially applied or scanners shifted), but `www.das.nl` (274k) is now the dominant Bot300700 source and was not separately sized in the previous round. Open the **same** conversation the addendum opened on `assets.das.nl`/auth hosts — does platform recognise these source IPs as our monitors, or are they scanners? Until that lands, Bot300700 is still REVIEW.

The IAM-team conversation on Bot300xxx + 920320 on `/auth/login` across the five auth hosts (`mijn`, `inloggen`, `mijndas`, `mijndossier`, `mijnpolis`) — open in the addendum (TODO #3) — is unchanged.

## 6. 933210 PHP injection — globally-disabled override is partly in place

14d events: 69 total, all with `action_s = AnomalyScoring` (no `Log` or `Block` action recorded). The disable override is keeping the rule from firing as an explicit Log/Block but the rule still contributes to anomaly score. Low risk; flag to whoever owns the Bicep policy to confirm whether "Disabled" was the action they applied or whether they need to drop the anomaly contribution as well.

## 7. Residual if we flipped CRS today

Anomaly score (rule 949110) events over 14d, by host:

| Host                | 14d events |
| ------------------- | ---------: |
| `mijn.das.nl`       |     65,892 |
| `metrics.das.nl`    |     24,576 |
| `adviseur.das.nl`   |     22,020 |
| `www.das.nl`        |     10,683 |
| `inloggen.das.nl`   |      5,640 |
| `adviseurs.das.nl`  |      4,503 |
| `mijndas.das.nl`    |      1,721 |
| `assets.das.nl`     |        818 |
| `mijndossier.das.nl`|        413 |
| `mijnpolis.das.nl`  |        332 |
| **Total**           | **136,598** |

That's the upper bound on CRS-driven blocks if we removed the Log overrides today **without** adding the four new exclusions in §2. Most of `metrics` (24k) and a large fraction of `mijn` / `adviseur` is exactly the new-FP-selector pile. Adding the §2 exclusions should drop this total by an estimated **20–40%** (rough — `ep.*` + `_csrfSecret` + `ai_*` + `__txn_*` collectively dominate the residual scoring on `mijn`/`metrics`).

## Recommended next steps

In order, before flipping CRS to Block:

1. **Add the four new exclusions** from §2 (`ep.*`, `_csrfSecret`, `ai_user`, `ai_session`, `__txn_*`). Update `waf_triage.py` predicates in lockstep. *(Bicep change applied 2026-05-26 in `network/FrontDoor/parameters.{p,a}.bicepparam`; pending deploy.)*
2. **Confirm `__txn_*` PII status with the web team** (§3) — exclusion must not paper over a regression of the original `transaction` cookie issue.
3. **Sanity-check `returnTo` allow-listing with the auth team** (§4) — confirm app-side validation rejects off-domain / probe-path values before promoting `ProbePathLog`.
4. **Promote `ProbePathLog` / `ProbePathLog2` to Block.**
5. **Wait 48h. Re-run this assessment.** If the §2 exclusions land cleanly, the 949110 total should drop into the 80–110k / 14d range.
6. **Remove the Log overrides on CRS rules** — actual Detection→Prevention.
7. **Re-run again 7d post-cutover** and confirm the Block stream is dominated by BadBots + ProbePath + Geo, not by CRS false positives.

Open items carried over from the addendum (TODOs #1–6, unchanged): platform identification of Azure-range scanners, IAM cross-reference on `/auth/login`, integrations inventory for missing-header rules, `ms-office` UA allowance for newsletter images, `adviseur.das.nl` live-vs-legacy.

## How to reproduce

```bash
WS=abcf8641-4b47-4e6a-a6cc-b29ddb6d0351
# Action breakdown
az monitor log-analytics query -w $WS --analytics-query \
  "AzureDiagnostics
   | where Category == 'FrontDoorWebApplicationFirewallLog'
       and TimeGenerated between (datetime(2026-05-12) .. datetime(2026-05-26))
   | summarize n=count() by action_s
   | order by n desc" -o table

# Top selectors for a noisy rule (substitute the 5-digit rule id)
az monitor log-analytics query -w $WS --analytics-query \
  "AzureDiagnostics
   | where Category == 'FrontDoorWebApplicationFirewallLog'
       and TimeGenerated between (datetime(2026-05-12) .. datetime(2026-05-26))
       and ruleName_s endswith '942100'
   | extend mv = extract('\"matchVariableName\":\"([^\"]+)\"', 1, details_matches_s)
   | summarize n=count() by mv
   | top 15 by n" -o table
```

The classifier predicates in `waf_triage.py` still apply for any sample CSV export from this window; the §2 changes are the only update needed there.
