# Front Door WAF — 90-day KQL validation

**Status:** addendum to `waf_triage_writeup.md`
**Date:** 2026-05-06
**Scope:** validate the 15k-row CSV findings against the full 90-day population in Log Analytics
**Workspace:** `log-frontdoor-p-we-001` (`abcf8641-4b47-4e6a-a6cc-b29ddb6d0351`)
**Table / category:** `AzureDiagnostics` where `Category == "FrontDoorWebApplicationFirewallLog"`

## Why this exists

The CSV the original triage was built from is ~15,000 rows. KQL says the WAF
emits **130k–530k events per day**, ~9.4M in the inspected 90-day window —
the CSV is roughly **0.15%** of the population. That's enough to identify FP
_shapes_ (every payload variant tends to appear), but not enough to size them,
nor to surface long-tail hosts/paths/selectors that don't fall into the
recent-most slice. This addendum closes that gap.

## Methodology

The CSV stays the source of truth for **exclusion design**. It carries full
payloads, so reading what each rule actually tripped on is fast and visual.
KQL is used for **coverage and sizing only**:

1. Are the CSV-derived FP exclusions hitting the dominant selectors at scale?
2. Do new selectors / hosts / paths show up that the CSV missed?
3. What does the residual (post-exclusion) BLOCK pile actually look like?

Two principles shaped the queries:

- **Aggregate-only.** No raw row exports. Every query reduces to counts by
  `ruleName_s × matchVariableName × host × path`. The queries stay cheap and
  we don't re-import payloads we already analysed in the CSV.
- **Slice on the selector, not on the rule.** Azure Front Door exclusions
  scope on `matchVariable` + selector (cookie name / query-arg name), so the
  diagnostic question for any noisy rule is always "what selector dominates
  its triggers?". The workhorse expression is:

  ```kql
  extend mv = extract('"matchVariableName":"([^"]+)"', 1, details_matches_s)
  ```

Each query covered the full 90-day window; output was kept to the top-N rows
per dimension to keep results small.

## Findings

### 0. Framing fix — the policy is already in Prevention

Action breakdown over 90 days:

| `action_s`       | 90d events | what it represents                                      |
| ---------------- | ---------: | ------------------------------------------------------- |
| `AnomalyScoring` |  5,840,127 | post-evaluation rollup (rule 949110)                    |
| `Log`            |  4,745,727 | CRS rule trips — all currently overridden to Log        |
| `Allow`          |    161,653 | GoodBots ruleset                                        |
| `Block`          |     96,275 | **only** BadBots + GeoBlocking — zero CRS blocks in 90d |

The original writeup says "today the WAF is in detection". That's loose. The
policy `policyMode_s` is already `prevention`; what's in detection is the
**CRS ruleset itself**, via per-rule action overrides set to `Log`. The
cutover is "remove the Log overrides on CRS rules", not "flip the policy
mode". This matters for the change-control narrative.

### 1. CSV exclusions hold at scale (and one is missing)

For each high-volume CRS rule, the dominant selector matches what the
CSV-derived exclusions already cover:

| Rule        | Top selector (90d count)    | Already excluded? |
| ----------- | --------------------------- | ----------------- |
| 942100 SQLI | `sst.us_privacy` (1.16M)    | yes (GA4 STA)     |
| 942100 SQLI | `ttcsid` / `ttcsid_*` (28k) | yes               |
| 942100 SQLI | `CookieConsent` (956)       | yes               |
| 931130 RFI  | `dl` (1.18M)                | yes (GA4)         |
| 931130 RFI  | `iss` (146k)                | yes (OIDC)        |
| 931130 RFI  | `origin` (103k)             | yes (OIDC)        |
| 931130 RFI  | **`komtvan` (51k)**         | **no — add it**   |
| 931130 RFI  | `redirect_uri` (1k)         | no — see below    |

**New exclusion proposed:** `QueryParamValue:komtvan` on
`metrics.das.nl/g/collect`. Same shape as `dl`/`dr` — Dutch attribution
parameter ("komt van" → "comes from") carrying absolute URLs to the GA4
collector. 51,276 RFI-931130 + 717 XSS-941100 hits, all on `metrics.das.nl`.
Same residual-risk profile as the rest of the GA4 set in row 1 of the
original exclusion table.

**`redirect_uri` (1,071 events):** mostly `/` and a synthetic
`/realms/master/protocol/openid-connect/auth` that hits _every_ host with
identical 36-event volume — that's a Keycloak admin probe scanning the
Front Door fleet, not legitimate OIDC. Keep as residual block.

### 2. Hosts the 15k sample missed

The CSV covered `www`, `mijn`, `adviseurs`, `metrics`. KQL surfaced six more,
all with non-trivial volume:

| Host                 | 90d events | Notable                                              |
| -------------------- | ---------: | ---------------------------------------------------- |
| `assets.das.nl`      |    518,249 | image CDN; 475k Bot300700 on `.jpg/.jpeg/.png/.pdf`  |
| `adviseur.das.nl`    |    214,159 | **distinct from `adviseurs.das.nl`** — likely legacy |
| `inloggen.das.nl`    |     88,701 | auth host; Bot300xxx + 920320 same as `mijn`         |
| `mijndas.das.nl`     |     59,598 | auth host                                            |
| `mijndossier.das.nl` |     26,196 | auth host                                            |
| `mijnpolis.das.nl`   |     24,343 | auth host                                            |

Two follow-ups worth raising:

- **`assets.das.nl` Bot300700 on images (475k).** Unidentified-bot traffic
  hot-linking or scraping static images. Blocking this gains no security
  (image fetches don't expose application surface). Either custom-allow
  Bot300700 for asset paths, or accept Bot300700 as Log-only on this host.
  This is **the largest single source of REVIEW noise** (475k of ~1.4M total
  Bot300700 events at the policy level).
- **`adviseur.das.nl` (singular)** — confirm with platform whether this is a
  live host or a legacy redirect target. The XSS-9411xx hits there all map to
  `HeaderValue:referer` / `HeaderValue:user-agent` — pure scanner traffic,
  not application FPs. PHP-933210 also fires here, already globally disabled.

The four `mijn*` / `inloggen` auth hosts repeat the `mijn.das.nl` pattern
(Bot300xxx + 920320 missing-UA), so the CSV-era REVIEW notes for `mijn`
generalise — the IAM-team conversation needs to cover all five hosts as one
question, not five separate ones.

### 3. Probe inventory — high-confidence custom-block candidates

90-day path scan for canonical probe patterns:

| Path                                                | Events |  IPs |
| --------------------------------------------------- | -----: | ---: |
| `/AutoDiscover/autodiscover.xml`                    | 25,708 | 1560 |
| `/xmlrpc.php`                                       |  8,671 |  191 |
| `/wp-admin/index.php`                               |  6,907 |   18 |
| `/wp-login.php`                                     |  4,608 |  140 |
| `/wp-content/plugins/hellopress/wp_filemanager.php` |  2,524 |  238 |
| `/.env`                                             |  1,345 |  128 |
| `/wp-admin/admin-ajax.php`                          |  1,172 |   16 |
| `/.git/config`                                      |    993 |  107 |
| `/realms/master/protocol/openid-connect/auth`       |    969 |    1 |
| `/setup/index.php`                                  |    887 |    4 |

DAS doesn't run WordPress, PHP, on-prem Exchange, or Keycloak admin behind
Front Door. These are unambiguous probes. A custom-rule block on path
prefixes — `/wp-`, `/.env`, `/.git`, `/AutoDiscover`, `/setup/`,
`/realms/master/`, `/cgi-bin/`, `/HNAP1`, `/manager/html`, `/_profiler`,
`/actuator/`, `/console/` — clears ~50k events of REVIEW noise and is much
clearer to operate than relying on Bot300700 + human triage. This is a net
new recommendation that the CSV didn't have the volume to justify on its own.

Spring4Shell-style probe `class.module.classLoader.resources.context.configFile`
also showed up in the 931130 selector list (284 hits) — same custom-block
treatment.

### 4. Top blockers (already enforced — for context)

| Source IP         | 90d blocks | Rule          |
| ----------------- | ---------: | ------------- |
| 193.32.162.28     |      6,378 | GeoBlocking   |
| 31.160.12.33      |      1,649 | BadBot-100200 |
| 20.220.213.131    |      1,296 | BadBot-100100 |
| 172.94.9.253      |        629 | GeoBlocking   |
| `220.181.51.0/24` |     ~2,500 | GeoBlocking   |

The `220.181.51.0/24` cluster (Baidu range) is one logical actor spread
across ~12 IPs. If GeoBlocking ever loosens, that /24 is a candidate for a
custom deny.

## Updates to the rollout plan

1. **Add `komtvan`** to `EXCLUDED_QUERY_PARAM_NAMES` in `waf_triage.py` and
   to `QueryStringArgNames` in the Bicep policy.
2. **Add a custom block rule** for the probe-path prefixes in section 3.
   Reduces REVIEW noise and shortens the path to enforcement.
3. **Decide on `assets.das.nl`** — custom-allow Bot300700 for asset paths or
   accept it as Log-only. Currently the largest single REVIEW contributor.
4. **Confirm `adviseur.das.nl` (singular)** with platform — live or legacy?
5. **Re-run after cutover.** The 90d CRS-Block count is `0`. The post-cutover
   risk is the FP volume on the currently-Log CRS rules, which is exactly
   what the exclusion set is sized against. Re-run the script (CSV or
   equivalent KQL aggregations) 48h after removing the rule overrides and
   verify residuals match the sample.

## Conclusion — consolidated rollout plan

Combining the original writeup and this addendum, the WAF cutover comes down
to four ruleset changes and a short list of follow-ups to confirm with other
teams before flipping CRS rule actions.

### Proposed WAF policy changes

**A. Managed-rule exclusions** — the deployed policy already encodes most of
these; the only addition from the 90-day analysis is `komtvan`.

| #   | Type                | Selector                                             | Source           |
| --- | ------------------- | ---------------------------------------------------- | ---------------- |
| 1   | RequestCookieNames  | Equals: `CookieConsent`                              | original writeup |
| 2   | RequestCookieNames  | Equals: `transaction`                                | original writeup |
| 3   | RequestCookieNames  | Equals: `FPID`, `FPLC`                               | original writeup |
| 4   | RequestCookieNames  | StartsWith: `__session__`, `ttcsid`                  | original writeup |
| 5   | RequestCookieNames  | Contains: `UMBREMBR`                                 | legacy           |
| 6   | QueryStringArgNames | Equals: `dl`, `dr`, `uafvl`, `uam`, `sst.us_privacy` | original writeup |
| 7   | QueryStringArgNames | Equals: `iss`, `returnUrl`, `origin`                 | original writeup |
| 8   | QueryStringArgNames | Equals: `token`                                      | legacy           |
| 9   | QueryStringArgNames | **Equals: `komtvan`** ← **new**                      | **addendum §1**  |

**B. Globally disabled CRS rules** (ruleGroupOverrides → action=Disabled):

| Rule   | Reason                                                     |
| ------ | ---------------------------------------------------------- |
| 933210 | PHP injection — DAS has no PHP; trips on Next.js `(route)` |

**C. New custom block rule — probe paths.** Match `requestUri` path-prefix
(case-insensitive) against any of:

```
/wp-          /.env         /.git         /AutoDiscover
/setup/       /realms/      /cgi-bin/     /HNAP1
/manager/html /_profiler    /actuator/    /console/
/phpmyadmin   /xmlrpc       /owa/         /ecp/
```

Action: Block. Priority: above the managed ruleset so these never reach the
CRS evaluation. Clears ~50k events of REVIEW noise and removes the need for
human triage on Bot300700-on-probe-path traffic.

**D. New custom rule — `assets.das.nl` Bot300700.** Either:

- (preferred) Allow Bot300700 for `host == assets.das.nl AND path startswith /` —
  silences ~475k REVIEW events that don't represent application risk; or
- Override Bot300700 to action=Log on this host only and accept it as
  permanent informational noise.

Decide once with the platform team; both options are reversible.

### Operational TODOs to confirm before the CRS cutover

| #   | Owner            | Question                                                                                                                                                                                                             |
| --- | ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Platform         | Is `adviseur.das.nl` (singular) live, legacy, or a redirect target? Should it route through this WAF policy?                                                                                                         |
| 2   | Platform         | Identify the Microsoft-Azure-range scanners (`4.180.149.225`, `52.136.212.3`, `51.136.91.19`) hitting `/auth/login` — our monitors? If yes, custom-allow them.                                                       |
| 3   | IAM              | Cross-reference Bot300700 hits on `/auth/login` against failed-login rates across **all five** auth hosts (`mijn`, `inloggen`, `mijndas`, `mijndossier`, `mijnpolis`) — credential stuffing vs. legitimate scanners? |
| 4   | Email / Exchange | Confirm we don't expose any on-prem Exchange via Front Door before enforcing the `/AutoDiscover` block.                                                                                                              |
| 5   | Integrations     | Inventory server-to-server clients that may legitimately omit `Accept` (920300) or `User-Agent` (920320) headers — anything that breaks under enforcement?                                                           |
| 6   | Marketing / Web  | Allow `ms-office` UA on `/-/media/*` and `assets.das.nl/*/logo.*` so Outlook image prefetch doesn't break newsletter rendering.                                                                                      |
| 7   | Web / App        | **PII finding** — fix the `transaction` cookie on `www.das.nl` (claim ID + customer name in plaintext). Out of WAF scope but surfaced by this work.                                                                  |
| 8   | Security         | After A–C are deployed, re-run `waf_triage.py` (or the equivalent KQL aggregations) 48h post-cutover. Residuals should match the sample; if not, iterate.                                                            |

### Cutover sequence

1. Deploy A (exclusions incl. `komtvan`), B (933210 disable unchanged), C
   (probe-path block), D (`assets.das.nl` decision). Keep CRS rules in `Log`.
2. Wait 48h. Re-run the triage. Confirm residual matches expectation.
3. Resolve TODOs 1–6 with the respective teams.
4. Remove the `Log` action overrides on CRS rules — this is the actual
   "Detection → Prevention" flip.
5. Monitor `Block` action volume for 1 week; expect a step-up from ~96k/90d
   (BadBot+Geo only) to a higher steady state dominated by the new
   probe-path custom rule and the BadBots family. Anything else means a new
   FP pattern → iterate on exclusions.
6. Resolve TODO 7 (transaction-cookie PII) on its own track; it's not
   blocking the WAF rollout.

## Reproducing the queries

The Azure CLI shape used throughout:

```bash
WS=abcf8641-4b47-4e6a-a6cc-b29ddb6d0351   # log-frontdoor-p-we-001
az monitor log-analytics query -w $WS --analytics-query "<KQL>" -o table
```

Useful starting points:

```kql
// Top selectors for any noisy rule
AzureDiagnostics
| where Category == "FrontDoorWebApplicationFirewallLog"
    and TimeGenerated > ago(90d)
    and ruleName_s endswith "942100"
| extend mv = extract('"matchVariableName":"([^"]+)"', 1, details_matches_s)
| summarize n=count() by mv
| top 15 by n

// Per-host rule fingerprint (find FP patterns specific to one host)
AzureDiagnostics
| where Category == "FrontDoorWebApplicationFirewallLog"
    and TimeGenerated > ago(90d)
    and host_s == "<host>"
    and ruleName_s !endswith "949110"
| summarize n=count() by ruleName_s
| top 20 by n

// Probe-path inventory
AzureDiagnostics
| where Category == "FrontDoorWebApplicationFirewallLog"
    and TimeGenerated > ago(90d)
| extend path = tostring(parse_url(requestUri_s).Path)
| where path matches regex "(?i)(/wp-|/\\.env|/\\.git|/phpmyadmin|/setup/|/owa/|/ecp/|/autodiscover|/xmlrpc|/realms/|/cgi-bin)"
| summarize n=count(), ips=dcount(clientIP_s) by path
| top 25 by n
```
