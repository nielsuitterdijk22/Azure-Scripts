#!/usr/bin/env bash
set -euo pipefail

# Configuration
BASE_URL="${APIM_BASE_URL:-https://api-d.das.nl}"
OCP="${APIM_OCP_KEY:-ba17ba4d2738492faf6fc9390efd1676}"
JWPI_KEY="6019fdd4873a4c768d71ec65e601546a"
DMSI_KEY="4e0c693c7d4549c6a80b7c2500eb15ea"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Counters
PASSED=0
FAILED=0
SKIPPED=0

# Test runner
run_test() {
    local name="$1"
    local expected="${2:-200}"  # Expected HTTP status, default 200
    shift 2

    printf "  %-50s " "$name"

    # Run curl and capture HTTP status code
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "$@" 2>/dev/null) || http_code="000"

    if [[ "$http_code" == "$expected" ]]; then
        echo -e "${GREEN}✓ PASS${NC} (HTTP $http_code)"
        ((++PASSED))
    elif [[ "$http_code" == "000" ]]; then
        echo -e "${RED}✗ FAIL${NC} (connection error)"
        ((++FAILED))
    else
        echo -e "${RED}✗ FAIL${NC} (HTTP $http_code, expected $expected)"
        ((++FAILED))
    fi
    return 0
}

skip_test() {
    local name="$1"
    local reason="$2"
    printf "  %-50s " "$name"
    echo -e "${YELLOW}○ SKIP${NC} ($reason)"
    ((++SKIPPED))
}

# Test with body pattern matching
run_test_body() {
    local name="$1"
    local expected="$2"
    local pattern="$3"
    shift 3

    printf "  %-50s " "$name"

    local tmpfile
    tmpfile=$(mktemp)
    local http_code
    http_code=$(curl -s -o "$tmpfile" -w "%{http_code}" "$@" 2>/dev/null) || http_code="000"

    local body_match=false
    if grep -q "$pattern" "$tmpfile" 2>/dev/null; then
        body_match=true
    fi
    rm -f "$tmpfile"

    if [[ "$http_code" == "$expected" && "$body_match" == "true" ]]; then
        echo -e "${GREEN}✓ PASS${NC} (HTTP $http_code, body matched)"
        ((++PASSED))
    elif [[ "$http_code" == "000" ]]; then
        echo -e "${RED}✗ FAIL${NC} (connection error)"
        ((++FAILED))
    elif [[ "$http_code" != "$expected" ]]; then
        echo -e "${RED}✗ FAIL${NC} (HTTP $http_code, expected $expected)"
        ((++FAILED))
    else
        echo -e "${RED}✗ FAIL${NC} (HTTP $http_code OK, but body pattern not found)"
        ((++FAILED))
    fi
    return 0
}

section() {
    echo ""
    echo -e "${BLUE}${BOLD}━━━ $1 ━━━${NC}"
}

# Header
echo -e "${CYAN}${BOLD}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║              APIM Endpoint Test Suite                      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "Target: ${BOLD}$BASE_URL${NC}"
echo -e "Time:   $(date '+%Y-%m-%d %H:%M:%S')"

# ─────────────────────────────────────────────────────────────────
section "Health & Status"
# ─────────────────────────────────────────────────────────────────

run_test "APIM Status" 200 \
    "$BASE_URL/status-0123456789abcdef" --max-time 5

run_test "DMSI Functions Healthcheck" 200 \
    "$BASE_URL/dmsi-functions/v1/healthcheck/hc" \
    -H "Ocp-Apim-Subscription-Key: $DMSI_KEY"

# run_test "DMS Auth Hello" 200 \
#     "$BASE_URL/dmsauth/systemconfig/hello" \
#     -H "Ocp-Apim-Subscription-Key: $DMSI_KEY"

run_test "DMS Content Ping" 200 \
    "$BASE_URL/dmscontent/v1/ping" \
    -H "Ocp-Apim-Subscription-Key: $DMSI_KEY"

# ─────────────────────────────────────────────────────────────────
section "JWPI API"
# ─────────────────────────────────────────────────────────────────

run_test "JWPI System Healthcheck" 200 \
    "$BASE_URL/jwpi/api/v1/System/healthcheck" \
    -H "Ocp-Apim-Subscription-Key: $JWPI_KEY" \
    -H "Personeelsnummer: 456600"

run_test "JWPI Relaties Adressen" 200 \
    "$BASE_URL/jwpi/api/v1/Relaties/23485171/adressen/2" \
    -H "Ocp-Apim-Subscription-Key: $JWPI_KEY" \
    -H "Personeelsnummer: 456600"

run_test "JWPI Relaties Financiele Nummers" 404 \
    "$BASE_URL/jwpi/api/v1/Relaties/23485171/financielenummers/2" \
    -H "Ocp-Apim-Subscription-Key: $JWPI_KEY" \
    -H "Personeelsnummer: 456600"

# Expected to fail - requires OAuth token
skip_test "JWPI Documenten" "requires OAuth token"

# ─────────────────────────────────────────────────────────────────
section "Claims API"
# ─────────────────────────────────────────────────────────────────

run_test_body "Claims (expects 401 Unauthorized)" 401 "Unauthorized" \
    "$BASE_URL/claims/v1/claims" \
    -H "Authorization: Bearer test.mijndas" \
    -H "Ocp-Apim-Subscription-Key: $OCP" \
    -H "Content-Type: application/json"

# ─────────────────────────────────────────────────────────────────
section "Business Services"
# ─────────────────────────────────────────────────────────────────

run_test "Intermediaries" 200 \
    "$BASE_URL/Intermediaries/V1/GetIntermediaries" \
    -H "Ocp-Apim-Subscription-Key: $OCP"

run_test "KVK Bedrijven Search" 200 \
    "$BASE_URL/kvk/V1/selecteerbedrijven?bedrijfsnaam=DAS" \
    -H "Ocp-Apim-Subscription-Key: $OCP"

run_test "Accounts Get" 200 \
    "$BASE_URL/accounts/v1/getaccount/auth0|e1be74b2-ea7f-424a-9170-316d92ccd612" \
    -H "Ocp-Apim-Subscription-Key: $OCP"

run_test "Compliancy Check" 200 \
    "$BASE_URL/compliancycheck/V1/compliancycheck" \
    -H "Ocp-Apim-Subscription-Key: $OCP" \
    -H "Content-Type: application/json" \
    -d '{"voorletters":"A","naam":"RECHTSBIJSTAND","geboortedatum":"19850301","business_logic_code":"ALL","max_hits":5,"plaats":"AMSTERDAM","land":"NEDERLAND"}'

# ─────────────────────────────────────────────────────────────────
section "IF100 Postcode Service"
# ─────────────────────────────────────────────────────────────────

run_test "Postcode Lookup (1441SL)" 200 \
    "$BASE_URL/if100/V1/Postcode/IF100_PostcodeRS?postcode=1441SL&huisnummer=69" \
    -H "Ocp-Apim-Subscription-Key: $OCP"

run_test "Postcode Lookup (1031HK)" 200 \
    "$BASE_URL/if100/V1/Postcode/IF100_PostcodeRS?postcode=1031HK&huisnummer=74" \
    -H "Ocp-Apim-Subscription-Key: $OCP"

# ─────────────────────────────────────────────────────────────────
section "CED Service"
# ─────────────────────────────────────────────────────────────────

# CED payload
CED_PAYLOAD='{"Opdrachtgevercode":17751,"Meldercode":333,"Werkzaamheid":"SV","Object":"21","Dekking":"RB","Oorzaak":"115","Schadedatum":"2023-05-03T12:00:00Z","Polisnummer":"POLIS12345","Opdrachtnummer":"REF-123","Schadenummer":"1.23.057013","Schadeclaim":1300,"Verzekerd_bedrag":0,"Polisvoorwaarden":"","Opmerking":"Dit is een Test MCP rest opdrachten van DAS","Opmerking_uitgebreid":"","Aktevancessie":false,"Schadeplaats":"A","Soortsysteem":"MCP","Dossier_retour":true,"Eigen_risico":0,"Verhaalbaar":false,"BTWVerrekenbaar":false,"Waardevermindering":true,"Behandelaar":{"Naam":"Afdeling Expertise","Telefoonnummer":"020-6518888","Email":"expertise@das.nl"},"Voertuig":{"Kenteken":"7-TFS-14","Voertuigmerk":"PEUGEOT","Voertuigtype":"308","Kleur":"","Brandstof":"","HistorischeBPM":0,"MassaLedigGewicht":0,"Landcode":"NL"},"BetrokkenPartijen":[{"Rolcode":"VE","Naam":"Nawabi","Tussenvoegsel":"","Voorletters":"MZ","Straat":"Aldenhof","Huisnummer":3060,"Huisnummer_appendix":"","Postcode":"6537AE","Woonplaats":"NIJMEGEN","Telefoonnummer1":"06-12345678","Telefoonnummer2":"06-12345678","Telefoonnummer3":"06-12345678","Geslacht":"","Ibanrekeningnummer":"0","Emailadres":"im.advice@ced.nl","Opmerking":"Geen"},{"Rolcode":"BE","Naam":"CED hersteller","Tussenvoegsel":"","Voorletters":"","Straat":"Rietbaan","Huisnummer":40,"Huisnummer_appendix":"","Postcode":"2908LP","Woonplaats":"Capelle aan den IJssel","Telefoonnummer1":"06-12345678","Telefoonnummer2":"06-12345678","Telefoonnummer3":"06-12345678","Geslacht":"","Ibanrekeningnummer":"0","Emailadres":"im.advice@ced.nl","Opmerking":"Geen"}],"Totaal_verlies":false,"Waarborgfonds":false}'

run_test "CED Plaats Opdracht" 200 \
    "$BASE_URL/ced/V1/plaatsopdracht" \
    -H "Ocp-Apim-Subscription-Key: $OCP" \
    -H "Content-Type: application/json" \
    -d "$CED_PAYLOAD"

# ─────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════${NC}"
TOTAL=$((PASSED + FAILED + SKIPPED))

echo -e "${BOLD}Results:${NC}"
echo -e "  ${GREEN}Passed:${NC}  $PASSED"
echo -e "  ${RED}Failed:${NC}  $FAILED"
echo -e "  ${YELLOW}Skipped:${NC} $SKIPPED"
echo -e "  ${BOLD}Total:${NC}   $TOTAL"
echo ""

if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}✓ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}${BOLD}✗ $FAILED test(s) failed${NC}"
    exit 1
fi

