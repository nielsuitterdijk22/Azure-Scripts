#!/usr/bin/env python3
"""
waf_triage.py — classify Azure Front Door WAF log rows against a codified
exclusion set so we can move from Detection to Prevention mode with
confidence.

Input:  CSV exported from Log Analytics with the columns
        TimeGenerated [UTC], requestUri_s, ruleName_s, clientIP_s,
        details_matches_s, details_msg_s, details_data_s

Output: a triage report on stdout with four sections:
        1. Bucket counts (FP_* / BLOCK_* / REVIEW_* / ALLOW / AGGREGATE)
        2. Codified exclusions (what to put in the WAF policy)
        3. Residual "would still block" — grouped by bucket, rule, host, path
        4. Top offender IPs and paths in the BLOCK and REVIEW buckets

Usage:  ./waf_triage.py path/to/query_data.csv
        ./waf_triage.py path/to/query_data.csv --json out/  # also write JSON

The classifier is intentionally strict: an exclusion only fires when the
host, rule id, and matchVariableName all line up with a known-safe pattern.
Anything that does not match a rule drops into REVIEW, not into FP.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable
from urllib.parse import urlparse


# --------------------------------------------------------------------------- #
# Codified exclusion set
# --------------------------------------------------------------------------- #
#
# Each entry is a function that, given a parsed Row, returns True when the
# row represents a known false positive that should be excluded from the
# managed rules. Keep these narrow: host + rule id + match variable.

DAS_HOST_SUFFIX = re.compile(r"^https://([a-z0-9-]+\.)*das\.nl(/|$)", re.IGNORECASE)
OIDC_ISSUER = "https://authentication.das.nl/"

# Rule-id suffix extracted from the tail of ruleName_s
RULE_ID_RE = re.compile(r"(\d{6,8})$")
BOT_RULE_RE = re.compile(r"(Bot\d{6})$")


def extract_rule_id(rule_name: str) -> str:
    """Return the numeric suffix of a rule (e.g. 942100) or the Bot id."""
    if not rule_name:
        return ""
    m = BOT_RULE_RE.search(rule_name)
    if m:
        return m.group(1)
    m = RULE_ID_RE.search(rule_name)
    if m:
        return m.group(1)
    return rule_name


@dataclass
class Row:
    time: str
    uri: str
    rule_name: str
    rule_id: str
    client_ip: str
    host: str
    path: str
    msg: str
    data: str
    match_var: str
    match_val: str

    @classmethod
    def from_csv(cls, raw: dict) -> "Row":
        uri = raw.get("requestUri_s") or ""
        parsed = urlparse(uri)
        rule_name = raw.get("ruleName_s") or ""
        match_var, match_val = _parse_first_match(raw.get("details_matches_s") or "")
        return cls(
            time=raw.get("TimeGenerated [UTC]") or raw.get("\ufeffTimeGenerated [UTC]", ""),
            uri=uri,
            rule_name=rule_name,
            rule_id=extract_rule_id(rule_name),
            client_ip=raw.get("clientIP_s", "") or "",
            host=(parsed.hostname or "").lower(),
            path=parsed.path or "/",
            msg=raw.get("details_msg_s", "") or "",
            data=raw.get("details_data_s", "") or "",
            match_var=match_var,
            match_val=match_val,
        )


def _parse_first_match(raw_matches: str) -> tuple[str, str]:
    """Extract (matchVariableName, matchVariableValue) from the details_matches_s JSON."""
    if not raw_matches:
        return "", ""
    try:
        arr = json.loads(raw_matches)
    except json.JSONDecodeError:
        return "", ""
    if not arr or not isinstance(arr, list):
        return "", ""
    first = arr[0]
    return first.get("matchVariableName", "") or "", first.get("matchVariableValue", "") or ""


# --- Exclusion predicates -------------------------------------------------- #
#
# These predicates mirror exactly what the Azure Front Door WAF policy in
#   LandingzoneManagement/network/FrontDoor/parameters.{p,a}.bicepparam
# suppresses. Azure WAF exclusions scope only on matchVariable + selector
# (cookie name / query-arg name), never on host or path, so the predicates
# below do the same. Re-running this script predicts the real residual that
# the deployed policy will produce.
#
# Update both this file AND the Bicep parameter files when adding a new
# exclusion — they need to stay in lockstep.

# RequestCookieNames — Equals
EXCLUDED_COOKIE_NAMES = {
    "CookieConsent",  # Cookiebot consent banner (JSON literal with stamp:'-1')
    "transaction",    # DAS claim intake cookie (JSON blob; also PII — see writeup)
    "FPID",           # Google Analytics first-party id
    "FPLC",           # Google Analytics first-party linker
}

# RequestCookieNames — StartsWith
EXCLUDED_COOKIE_NAME_PREFIXES = (
    "__session__",    # iron-session / next-auth JWE (__session__0, __session__1, ...)
    "ttcsid",         # TikTok Pixel first-party session (ttcsid, ttcsid_<PIXEL_ID>)
)

# RequestCookieNames — Contains (legacy exclusion, kept for parity)
EXCLUDED_COOKIE_NAME_CONTAINS = ("UMBREMBR",)

# QueryStringArgNames — Equals
#  - token           : legacy pre-existing exclusion
#  - dl, dr          : GA4 document location / referrer (absolute URLs)
#  - uafvl           : GA4 UA-CH brand list (`Chromium;146.0.7680.178|...`)
#  - uam             : GA4 device model (`moto g power (2022)`)
#  - sst.us_privacy  : GA4 Server-side Tagging privacy flag (`1---`)
#  - iss             : OIDC issuer (authentication.das.nl)
#  - returnUrl       : OIDC post-login return
#  - origin          : OIDC + GA4 service-worker bootstrap
EXCLUDED_QUERY_PARAM_NAMES = {
    "token",
    "dl", "dr", "uafvl", "uam", "sst.us_privacy",
    "iss", "returnUrl", "origin",
}

# Rule ids disabled globally via ruleGroupOverrides. Each rule id here is a
# deliberate choice (no PHP anywhere in the DAS stack → 933210 tripping on
# Next.js `(route)` path segments is pure noise).
GLOBALLY_DISABLED_RULE_IDS = {
    "933210",  # PHP injection via superglobals / parentheses
}


def _strip_prefix(match_var: str, prefix: str) -> str | None:
    if match_var.startswith(prefix):
        return match_var[len(prefix):]
    return None


def is_fp_excluded_cookie(r: Row) -> bool:
    """RequestCookieNames exclusion — cookie name matches Equals/StartsWith/Contains.

    Matches the `RequestCookieNames` exclusions block in the Bicep policy.
    Azure applies the exclusion globally (all rules in the ruleset), so this
    predicate does not filter on rule id.
    """
    name = _strip_prefix(r.match_var, "CookieValue:")
    if name is None:
        return False
    if name in EXCLUDED_COOKIE_NAMES:
        return True
    if any(name.startswith(p) for p in EXCLUDED_COOKIE_NAME_PREFIXES):
        return True
    if any(sub in name for sub in EXCLUDED_COOKIE_NAME_CONTAINS):
        return True
    return False


def is_fp_excluded_query_param(r: Row) -> bool:
    """QueryStringArgNames exclusion — query-arg name matches Equals.

    Matches the `QueryStringArgNames` exclusions block in the Bicep policy.
    Like the cookie exclusion, this is global across all rules in the ruleset.
    """
    name = _strip_prefix(r.match_var, "QueryParamValue:")
    if name is None:
        return False
    return name in EXCLUDED_QUERY_PARAM_NAMES


def is_fp_disabled_rule(r: Row) -> bool:
    """Rule disabled via ruleGroupOverrides — matches regardless of selector."""
    return r.rule_id in GLOBALLY_DISABLED_RULE_IDS


EXCLUSION_PREDICATES = [
    ("FP_EXCLUDED_COOKIE", is_fp_excluded_cookie),
    ("FP_EXCLUDED_QUERY_PARAM", is_fp_excluded_query_param),
    ("FP_DISABLED_RULE", is_fp_disabled_rule),
]


# --- Residual classifier --------------------------------------------------- #
#
# Buckets after exclusions are applied. Order matters: first match wins.

PROBE_PATH_RE = re.compile(
    r"/(autodiscover|wp-[^/]+|\.env|\.git|xmlrpc|phpmyadmin|owa|ecp|wordpress)",
    re.IGNORECASE,
)
MS_OFFICE_UA_RE = re.compile(r"ms-office|msoffice", re.IGNORECASE)


def classify_residual(r: Row) -> str:
    # Aggregate; never counted as an independent signal.
    if r.rule_id == "949110":
        return "AGGREGATE"

    if "GoodBots" in r.rule_name:
        return "ALLOW_GOODBOT"

    if "GeoBlocking" in r.rule_name:
        return "BLOCK_GEO"

    if "BadBots" in r.rule_name:
        return "BLOCK_BADBOT"

    if "MS-ThreatIntel" in r.rule_name:
        return "BLOCK_THREATINTEL"

    if MS_OFFICE_UA_RE.search(r.match_val):
        return "REVIEW_MS_OFFICE"

    if r.rule_id == "Bot300700":
        if PROBE_PATH_RE.search(r.path):
            return "REVIEW_BOT_PROBE"
        return "REVIEW_UNKNOWN_BOT"

    if r.rule_id.startswith("Bot300"):
        return "REVIEW_UNKNOWN_BOT"

    # Injection-family rules that survive the FP filter are suspicious by
    # construction — CRS only trips these on payloads, not on benign strings.
    if any(seg in r.rule_name for seg in ("-SQLI-", "-XSS-", "-RFI-", "-PHP-", "-LFI-", "-RCE-")):
        return "BLOCK_INJECTION"

    if "PROTOCOL-ENFORCEMENT" in r.rule_name:
        return "REVIEW_PROTOCOL"

    return "REVIEW_OTHER"


# --------------------------------------------------------------------------- #
# Processing
# --------------------------------------------------------------------------- #

@dataclass
class Report:
    bucket_counts: Counter = field(default_factory=Counter)
    exclusion_hits: dict[str, Counter] = field(
        default_factory=lambda: defaultdict(Counter)
    )
    residual_by_rule: dict[str, Counter] = field(
        default_factory=lambda: defaultdict(Counter)
    )
    residual_top_ips: dict[str, Counter] = field(
        default_factory=lambda: defaultdict(Counter)
    )
    residual_top_paths: dict[str, Counter] = field(
        default_factory=lambda: defaultdict(Counter)
    )
    total_rows: int = 0


def process(path: Path) -> Report:
    report = Report()
    with path.open(newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        for raw in reader:
            row = Row.from_csv(raw)
            report.total_rows += 1

            matched_exclusion: str | None = None
            for name, pred in EXCLUSION_PREDICATES:
                if pred(row):
                    matched_exclusion = name
                    break

            if matched_exclusion:
                report.bucket_counts[matched_exclusion] += 1
                key = (row.rule_id, row.host, row.match_var)
                report.exclusion_hits[matched_exclusion][key] += 1
                continue

            bucket = classify_residual(row)
            report.bucket_counts[bucket] += 1
            if bucket == "AGGREGATE":
                continue

            rule_key = f"{row.rule_id} ({row.rule_name.split('-')[0] if '-' not in row.rule_name else ' '.join(row.rule_name.split('-')[1:3])})"
            report.residual_by_rule[bucket][rule_key] += 1
            report.residual_top_ips[bucket][row.client_ip] += 1
            report.residual_top_paths[bucket][f"{row.host}{row.path}"] += 1

    return report


# --------------------------------------------------------------------------- #
# Rendering
# --------------------------------------------------------------------------- #

FP_BUCKETS = (
    "FP_EXCLUDED_COOKIE",
    "FP_EXCLUDED_QUERY_PARAM",
    "FP_DISABLED_RULE",
)

BUCKET_ORDER = [
    *FP_BUCKETS,
    "ALLOW_GOODBOT",
    "BLOCK_GEO",
    "BLOCK_BADBOT",
    "BLOCK_THREATINTEL",
    "BLOCK_INJECTION",
    "REVIEW_BOT_PROBE",
    "REVIEW_UNKNOWN_BOT",
    "REVIEW_MS_OFFICE",
    "REVIEW_PROTOCOL",
    "REVIEW_OTHER",
    "AGGREGATE",
]


def _hr(char: str = "-", width: int = 78) -> str:
    return char * width


def _render_bucket_counts(report: Report, p) -> None:
    p("\n[1] Bucket counts")
    p(_hr())
    total_classified = sum(report.bucket_counts.values())
    for bucket in BUCKET_ORDER:
        count = report.bucket_counts.get(bucket, 0)
        if count == 0:
            continue
        pct = count / report.total_rows * 100 if report.total_rows else 0
        p(f"  {bucket:<24s} {count:>6d}  ({pct:5.1f}%)")
    extras = set(report.bucket_counts) - set(BUCKET_ORDER)
    for bucket in sorted(extras):
        p(f"  {bucket:<24s} {report.bucket_counts[bucket]:>6d}")
    p(f"  {'TOTAL':<24s} {total_classified:>6d}")


def _render_exclusions(report: Report, p) -> None:
    p("\n[2] Codified exclusions (applied by the deployed WAF policy)")
    p(_hr())
    for bucket in FP_BUCKETS:
        hits = report.exclusion_hits.get(bucket)
        if not hits:
            continue
        total = sum(hits.values())
        p(f"\n  {bucket}  — suppresses {total} events")
        for (rule_id, host, match_var), count in hits.most_common():
            p(f"    - rule {rule_id:<12} host {host:<18} var {match_var:<34} {count:>5d}")


def _residual_buckets(report: Report) -> list[str]:
    return [
        b for b in BUCKET_ORDER
        if b.startswith(("BLOCK_", "REVIEW_")) and report.bucket_counts.get(b)
    ]


def _render_residual_rules(report: Report, p, residual: list[str]) -> None:
    p("\n[3] Residual after exclusions — would still fire in prevention mode")
    p(_hr())
    for bucket in residual:
        count = report.bucket_counts[bucket]
        p(f"\n  {bucket}  ({count})")
        for rule, c in report.residual_by_rule[bucket].most_common(8):
            p(f"      rule {rule:<55} {c:>5d}")


def _render_top(report: Report, p, residual: list[str], section: str, title: str, attr: str, width: int) -> None:
    p(f"\n{section} {title}")
    p(_hr())
    for bucket in residual:
        top = getattr(report, attr)[bucket].most_common(5)
        if not top:
            continue
        p(f"\n  {bucket}")
        for key, c in top:
            p(f"      {key:<{width}} {c:>5d}")


def render(report: Report, out=sys.stdout) -> None:
    def p(*a, **kw):
        print(*a, **kw, file=out)

    p(_hr("="))
    p(f"WAF triage report — {report.total_rows} rows")
    p(_hr("="))

    _render_bucket_counts(report, p)
    _render_exclusions(report, p)

    residual = _residual_buckets(report)
    _render_residual_rules(report, p, residual)
    _render_top(report, p, residual, "[4]", "Top source IPs in residual buckets", "residual_top_ips", 44)
    _render_top(report, p, residual, "[5]", "Top paths in residual buckets", "residual_top_paths", 60)
    p()


def write_json(report: Report, out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)

    exclusions = []
    for bucket, hits in report.exclusion_hits.items():
        for (rule_id, host, match_var), count in hits.items():
            exclusions.append(
                {
                    "bucket": bucket,
                    "rule_id": rule_id,
                    "host": host,
                    "match_variable": match_var,
                    "suppressed_events": count,
                }
            )
    (out_dir / "exclusions.json").write_text(json.dumps(exclusions, indent=2))

    block_candidates = []
    for bucket in BUCKET_ORDER:
        if not bucket.startswith("BLOCK_"):
            continue
        for rule, count in report.residual_by_rule.get(bucket, Counter()).most_common():
            block_candidates.append(
                {"bucket": bucket, "rule": rule, "events": count}
            )
    (out_dir / "block_candidates.json").write_text(
        json.dumps(block_candidates, indent=2)
    )


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv", type=Path, help="Path to the WAF log CSV export")
    parser.add_argument(
        "--json",
        type=Path,
        metavar="OUT_DIR",
        help="Also emit exclusions.json and block_candidates.json to this directory",
    )
    args = parser.parse_args(argv)

    if not args.csv.exists():
        print(f"error: {args.csv} not found", file=sys.stderr)
        return 2

    report = process(args.csv)
    render(report)
    if args.json:
        write_json(report, args.json)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
