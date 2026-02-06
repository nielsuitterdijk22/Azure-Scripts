#!/bin/bash

set -euo pipefail

PRIVATE_DNS_SERVER="${PRIVATE_DNS_SERVER:-}"
DOMAIN="${DOMAIN:-}"
RECORD_TYPES="${RECORD_TYPES:-A,AAAA,CNAME,MX,TXT,NS}"
VERBOSE="${VERBOSE:-false}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Compare private DNS zone records with public DNS records"
    echo ""
    echo "Options:"
    echo "  -s, --server SERVER          Private DNS server IP"
    echo "  -d, --domain DOMAIN          Domain to compare"
    echo "  -t, --types TYPES            Record types to check (default: A,AAAA,CNAME,MX,TXT,NS)"
    echo "  -v, --verbose                Verbose output"
    echo "  -h, --help                   Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  PRIVATE_DNS_SERVER           Private DNS server IP"
    echo "  DOMAIN                       Domain to compare"
    echo "  RECORD_TYPES                 Comma-separated record types"
    echo "  VERBOSE                      Set to 'true' for verbose output"
    echo ""
    echo "Examples:"
    echo "  $0 -s 10.0.0.10 -d example.com"
    echo "  $0 -s 10.0.0.10 -d example.com -t A,CNAME"
    exit 1
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

normalize_record() {
    local record="$1"
    echo "$record" | tr '[:upper:]' '[:lower:]' | sed 's/\.$//g' | sort
}

query_dns() {
    local server="$1"
    local domain="$2"
    local type="$3"

    log_verbose "Querying $type records for $domain from $server"

    if [[ "$server" == "public" ]]; then
        dig +short +time=5 +tries=2 "$domain" "$type" 2>/dev/null || echo ""
    else
        dig +short +time=5 +tries=2 "@$server" "$domain" "$type" 2>/dev/null || echo ""
    fi
}

compare_records() {
    local domain="$1"
    local type="$2"
    local private_server="$3"

    echo -e "\n${YELLOW}=== Comparing $type records for $domain ===${NC}"

    local private_records=$(query_dns "$private_server" "$domain" "$type")
    local public_records=$(query_dns "public" "$domain" "$type")

    local private_normalized=""
    local public_normalized=""

    if [[ -n "$private_records" ]]; then
        private_normalized=$(echo "$private_records" | normalize_record)
    fi

    if [[ -n "$public_records" ]]; then
        public_normalized=$(echo "$public_records" | normalize_record)
    fi

    log_verbose "Private records: $private_records"
    log_verbose "Public records: $public_records"

    if [[ -z "$private_records" && -z "$public_records" ]]; then
        echo -e "${BLUE}No $type records found in either zone${NC}"
        return
    fi

    if [[ -z "$private_records" ]]; then
        echo -e "${RED}❌ Private zone missing $type records${NC}"
        echo -e "   Public: $public_records"
        return
    fi

    if [[ -z "$public_records" ]]; then
        echo -e "${RED}❌ Public zone missing $type records${NC}"
        echo -e "   Private: $private_records"
        return
    fi

    if [[ "$private_normalized" == "$public_normalized" ]]; then
        echo -e "${GREEN}✅ $type records match${NC}"
        echo -e "   Records: $private_records"
    else
        echo -e "${RED}❌ $type records differ${NC}"
        echo -e "   Private:  $private_records"
        echo -e "   Public:   $public_records"

        echo ""
        echo "   Detailed comparison:"

        if [[ -n "$private_normalized" ]]; then
            while IFS= read -r record; do
                if echo "$public_normalized" | grep -qF "$record"; then
                    echo -e "   ${GREEN}  ✅ $record (in both)${NC}"
                else
                    echo -e "   ${RED}  ❌ $record (private only)${NC}"
                fi
            done <<< "$private_normalized"
        fi

        if [[ -n "$public_normalized" ]]; then
            while IFS= read -r record; do
                if ! echo "$private_normalized" | grep -qF "$record"; then
                    echo -e "   ${RED}  ❌ $record (public only)${NC}"
                fi
            done <<< "$public_normalized"
        fi
    fi
}

check_subdomains() {
    local domain="$1"
    local private_server="$2"

    echo -e "\n${YELLOW}=== Checking common subdomains ===${NC}"

    local subdomains=("www" "mail" "ftp" "api" "app" "portal" "admin" "dev" "test" "staging")

    for subdomain in "${subdomains[@]}"; do
        local full_domain="${subdomain}.${domain}"

        local has_private=$(query_dns "$private_server" "$full_domain" "A")
        local has_public=$(query_dns "public" "$full_domain" "A")

        if [[ -n "$has_private" || -n "$has_public" ]]; then
            echo -e "\n${BLUE}Found subdomain: $full_domain${NC}"
            for type in A AAAA CNAME; do
                compare_records "$full_domain" "$type" "$private_server"
            done
        fi
    done
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--server)
            PRIVATE_DNS_SERVER="$2"
            shift 2
            ;;
        -d|--domain)
            DOMAIN="$2"
            shift 2
            ;;
        -t|--types)
            RECORD_TYPES="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE="true"
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

if [[ -z "$PRIVATE_DNS_SERVER" ]]; then
    echo "Error: Private DNS server is required"
    usage
fi

if [[ -z "$DOMAIN" ]]; then
    echo "Error: Domain is required"
    usage
fi

if ! command -v dig >/dev/null 2>&1; then
    echo "Error: 'dig' command not found. Please install bind-utils or dnsutils package."
    exit 1
fi

echo -e "${BLUE}DNS Zone Comparison Tool${NC}"
echo "=========================="
echo "Private DNS Server: $PRIVATE_DNS_SERVER"
echo "Domain: $DOMAIN"
echo "Record Types: $RECORD_TYPES"
echo ""

if ! dig +time=5 +tries=2 "@$PRIVATE_DNS_SERVER" "$DOMAIN" A >/dev/null 2>&1; then
    echo -e "${RED}Error: Cannot reach private DNS server $PRIVATE_DNS_SERVER${NC}"
    exit 1
fi

IFS=',' read -ra types <<< "$RECORD_TYPES"

for type in "${types[@]}"; do
    type=$(echo "$type" | tr '[:lower:]' '[:upper:]' | xargs)
    compare_records "$DOMAIN" "$type" "$PRIVATE_DNS_SERVER"
done

check_subdomains "$DOMAIN" "$PRIVATE_DNS_SERVER"

echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo -e "${GREEN}Green ✅${NC} = Records match between private and public zones"
echo -e "${RED}Red ❌${NC} = Records differ or missing in one zone"
echo -e "${BLUE}Blue ℹ️${NC} = Informational messages"