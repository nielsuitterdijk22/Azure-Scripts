# Front Door WAF — Detection → Prevention plan

**Status:** draft for team review
**Scope:** the Azure Front Door WAF in front of `*.das.nl`
**Data:** 15,000 WAF detection events (most recent, from a 90-day window)
**Tool:** `_scripts/security/waf_triage.py` — run it against any Log Analytics CSV export with the same columns (`requestUri_s`, `ruleName_s`, `clientIP_s`, `details_matches_s`, `details_msg_s`, `details_data_s`) to re-classify.

## TL;DR

Today the WAF is in Detection. If we flipped it to Prevention tomorrow we would block ~8,100 legitimate requests against 15,000 total (54%). The failures are concentrated in six repeatable patterns, each covered by a narrow exclusion. After applying all six the residual ruleset would block **186 likely-malicious requests** and flag **~1,900 events for human review** (mostly unknown bots).

| Bucket                                           | Events | Action                                      |
| ------------------------------------------------ | -----: | ------------------------------------------- |
| FP — GA4 Measurement Protocol (`metrics.das.nl`) |  5,513 | Exclude                                     |
| FP — Cookiebot `CookieConsent` cookie            |  2,259 | Exclude                                     |
| FP — OIDC authorize flow (`/auth/login`)         |    258 | Exclude                                     |
| FP — Opaque session / tracking cookies           |     38 | Exclude                                     |
| FP — DAS application `transaction` cookie        |     22 | Exclude **(also: PII concern — see below)** |
| FP — Next.js route-group paths (`(authorized)`)  |     15 | Exclude                                     |
| ALLOW — verified GoodBots                        |    336 | No change (ruleset already allows)          |
| **BLOCK — GeoBlocking**                          |     27 | Enforce                                     |
| **BLOCK — BadBots (falsified identity)**         |    124 | Enforce                                     |
| **BLOCK — CRS injection (residual)**             |      2 | Enforce                                     |
| REVIEW — UnknownBots hitting auth/home           |  1,529 | Needs IAM team call                         |
| REVIEW — UnknownBots probing Exchange/WP         |     65 | Can go to block later                       |
| REVIEW — Protocol-enforcement (920300/920320)    |    219 | Needs sec+platform call                     |
| REVIEW — ms-office image prefetch                |     61 | Likely allow                                |
| (Aggregate anomaly score — informational)        |  4,532 | N/A                                         |

## The six exclusions (what we propose to configure)

Each exclusion is narrow: host + rule id + match variable. No wildcards on rule ids; no value-based logic (AFD doesn't support that anyway). For each exclusion the "evidence" is a real payload sample we saw in the 15k event window.

### 1. FP_METRICS_GA4 — 5,513 events

**Host:** `metrics.das.nl`
**Paths:** `/g/collect`, `/_/service_worker/*`
**What it is:** Google Analytics 4 server-side tagging. `metrics.das.nl` is a thin pass-through CNAME; traffic is proxied to Google's Measurement Protocol. Nothing on this host is interpreted as SQL/HTML by DAS application code.

**Rules to disable on this host:**

| Rule     | Family                   | Trip reason                                                |
| -------- | ------------------------ | ---------------------------------------------------------- | --------- |
| 920230   | Multiple URL encoding    | `uafvl` param carries UA-CH client hints serialized with ` | `and`%20` |
| 931120   | RFI URL included         | GA `dl` / `dr` are absolute URLs                           |
| 931130   | RFI off-domain reference | `dl`, `dr`, `origin` are legitimate off-domain values      |
| 941100   | XSS filter cat 1         | `dl` contains query strings GA reads as HTML               |
| 941120   | XSS filter cat 2         | Google first-party cookie `_FPLC` contains spaces + base64 |
| 942100   | SQLI libinjection        | `sst.us_privacy=1---` and TikTok `ttcsid_*` cookie         |
| 942300   | SQLI backtick            | `uafvl` brand string parses as backtick                    |
| 942410   | SQLI string termination  | `uam` (device model) like `"moto g power (2022)"`          |
| 99031003 | MS-ThreatIntel SQLI      | Same `uam` payload                                         |

**Residual risk:** negligible. If an attacker finds a vector at `metrics.das.nl`, it terminates at a GA collector, not DAS application infrastructure.

### 2. FP_COOKIECONSENT — 2,259 events

**Match variable:** `CookieValue:CookieConsent` (global, on every `*.das.nl` host we see Cookiebot deployed: `www`, `mijn`, `adviseurs`)
**What it is:** the Cookiebot consent cookie. The cookie is a JSON literal of the form `{stamp:'-1',necessary:true,...}`. The `'-1'` and `'...=='` substrings match SQLI auth-bypass and MySQL-comment rules.

**Rules to disable on this cookie:**
`942100`, `942200`, `942330`, `942340`, `99031002`, `99031004`.

**Residual risk:** none. The cookie is written by the Cookiebot banner script and read client-side. It is not a SQL parameter or a rendered HTML context anywhere.

### 3. FP_TRANSACTION_COOKIE — 22 events **⚠ privacy concern**

**Match variable:** `CookieValue:transaction`
**Host:** `www.das.nl`
**What it is:** a DAS application cookie set during the claim intake flow. The value is a JSON blob of the form:

```json
{"claimId":"5.26.029848","customerGender":"UNDEFINED","customerName":"Geachte heer Kloost…", …}
```

Same trip pattern as CookieConsent. Same rules, same reasoning, same exclusion.

**⚠ Separate finding — flag to the web team.** This cookie carries the customer name and claim ID in plaintext. That is PII in a client-readable cookie, sent on every request to `www.das.nl` (including static assets like fonts and `/_next/` chunks). Recommendation:

- Move the state server-side under a session id, or
- Encrypt the payload (JWE, same pattern as the `__session__*` cookies on `mijn.das.nl`), or
- At minimum, strip `customerName` / gender before storing.

This is out of scope for the WAF rollout but should not ship unresolved.

### 4. FP_OPAQUE_COOKIE — 38 events

**Match variables:** `CookieValue:__session__0`, `CookieValue:__session__1`, `CookieValue:ttcsid`, `CookieValue:ttcsid_*`, `CookieValue:FPLC`, `CookieValue:FPID`
**What they are:**

- `__session__0/1` — iron-session / next-auth JWE (encrypted) cookies. Payload is `{"enc":"A256GCM","alg":"dir"}..<base64 nonce>..<base64 ciphertext>`. Dots and dashes trip SQL comment / string-termination rules.
- `ttcsid*` — TikTok Pixel first-party session id. `::`-delimited numeric payload.
- `FPLC` / `FPID` — Google first-party client/linker cookies. Base64-ish.

**Rules to disable on these cookie names:**
SQLI family (`942100`, `942200`, `942210`, `942340`, `942450`, `99031002`, `99031004`) and XSS family (`941100`, `941101`, `941120`).

**Residual risk:** low. These values are never interpolated into SQL or rendered to HTML — they're opaque tokens read by middleware.

### 5. FP_NEXTJS_ROUTE_GROUP — 15 events

**Host:** `adviseurs.das.nl` (Next.js app-router deployment)
**Rule:** 933210 (PHP injection via superglobals/eval)
**Match variable:** `Path`
**What it is:** Next.js app-router supports route groups with `(segment)` syntax, e.g. `/_next/static/chunks/app/(authorized)/polissen/[id]/(details)/page-xxx.js`. CRS rule 933210 reads the parentheses as a PHP eval attempt. The asset is static JS; the stack is not PHP.

**Exclusion scope:** disable 933210 where `Path` contains `/_next/`.

**Residual risk:** none. If we ever add a PHP backend, re-evaluate.

### 6. FP_OIDC_AUTH — 258 events

**Hosts:** `mijn.das.nl`, `adviseurs.das.nl`
**Path:** `/auth/login`
**Rule:** 931130 (RFI off-domain reference)
**Match variables:** `QueryParamValue:iss`, `QueryParamValue:origin`, `QueryParamValue:returnUrl`
**What it is:** the OIDC authorization-code flow. `iss` is always the issuer URL, and for DAS that is **only** `https://authentication.das.nl/`. `origin`/`returnUrl` point at a `*.das.nl` property.

**Exclusion scope:** disable 931130 on `/auth/login` for these three query parameters.

**Residual risk:** the exclusion disables the off-domain-link rule on a single path only. The script verifies that every observed `iss` value is actually `https://authentication.das.nl/` and every `origin`/`returnUrl` lives on `*.das.nl` — if a new IdP gets added, the script will surface it as residual and we can update. **Confirmed with the user: `authentication.das.nl` is the only customer IdP.**

## What we'd still block (≈186 events)

Post-exclusions, the WAF in Prevention mode would block:

### GeoBlocking — 27 events

Already an explicit policy. Targets include obvious vacancy/HR pages (scraping for recruiter lead-gen) and homepage probes. Enforce.

Top offender: `193.32.162.28` (6 hits).

### BadBots-Bot100200 "falsified identity" — 124 events

User-agents masquerading as Safari 9 on macOS 10.11 fetching `/` repeatedly. Not a legitimate client mix in 2026. Enforce.

Top offender: `31.160.12.33` (20 hits).

### Residual CRS injection — 2 events

- 1× `941101` XSS on `HeaderValue:Referer` — legitimate-looking GA referrer with `_ga=` param. Low confidence; acceptable to block.
- 1× `931130` RFI on a Referer header we didn't match elsewhere.

These are individually trivial; good candidate for "block and see who complains".

## What goes to REVIEW (≈1,900 events)

### REVIEW_UNKNOWN_BOT — 1,529 events (Bot300xxx family)

**Top destinations are `mijn.das.nl/auth/login` (304) and `www.das.nl/` + `mijn.das.nl/` home pages.** This is either:

- automated scanners probing the login page, or
- legitimate monitoring / uptime-checker clients we haven't whitelisted.

Top source IPs `4.180.149.225` (136), `52.136.212.3` (103), `51.136.91.19` (38) are all **Microsoft Azure ranges** — probably our own uptime/synthetic monitoring. Needs confirmation from the platform team before enforcement.

**Action:** do not enforce until the IAM team reviews whether the `/auth/login` hits correlate with legit session-creation rates or are credential-stuffing. Separately, ask platform team to identify the Azure-origin monitors and add a custom rule to allow them.

### REVIEW_BOT_PROBE — 65 events

All 65 are a single IP `144.178.215.84` hitting `www.das.nl/AutoDiscover/autodiscover.xml` — classic Exchange/Outlook auto-discovery probing. Default action: enforce (block). Sanity check with email team that we don't run on-prem Exchange exposed via Front Door first.

### REVIEW_PROTOCOL — 219 events

- `920300` Missing Accept header: 170
- `920320` Missing User-Agent header: 49

Concentrated on `www.das.nl/AutoDiscover/autodiscover.xml` and homepage. Overlaps heavily with the BadBot and AutoDiscover probe sets — probably same actors. Default block is safe, but we'll see some real integrations break (server-to-server clients that don't send Accept). Needs a quick tour of known integrations.

### REVIEW_MS_OFFICE — 61 events

`Bot300400` "Service agents" with UA `Mozilla/4.0 (compatible; ms-office; MSOffice 16)` fetching images from `/-/media/images/das/mail/*` and `assets.das.nl/.../logo.png`. This is **Outlook prefetching images in marketing emails**. Block would be visible to recipients as missing logos in DAS marketing emails.

**Recommendation:** allow (custom rule allowing that UA for `*.das.nl/-/media/*` and asset paths).

## Proposed rollout

1. **Land the exclusions in the WAF policy** (6 rule-group exclusions as above). Keep the policy in Detection.
2. **Re-run `waf_triage.py` after 48h.** Residual should drop to the ranges above. If it doesn't, we have a new FP pattern and we iterate on the exclusion set.
3. **Run with the IAM team** — confirm the `mijn.das.nl/auth/login` Bot300700 hits are not credential stuffing in disguise (cross-reference with failed-login rates).
4. **Ask the platform team** to identify the Microsoft-range scanners hitting `/` and either whitelist them (if they're our monitors) or drop them into the block bucket.
5. **Decide on REVIEW_PROTOCOL** (920300/920320) — quick integration inventory.
6. **Flip to Prevention** with the exclusion set active and the reviewed buckets either allowed or blocked per the team discussions.
7. **Separately: fix the `transaction` cookie PII issue** (out of WAF scope, but surfaced by this exercise).

## How to reproduce

```
# From the _scripts repo root
python3 security/waf_triage.py path/to/query_data.csv
# Optional JSON artifacts (exclusions.json, block_candidates.json)
python3 security/waf_triage.py path/to/query_data.csv --json out/
```

The exclusion predicates live in `security/waf_triage.py` near the top of the file; adding a new pattern is a one-function change. The classifier is strict — anything it doesn't recognise goes to REVIEW, never to FP.
