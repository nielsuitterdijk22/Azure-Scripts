#!/bin/bash

set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-}"
PRIVATE_ZONE="${PRIVATE_ZONE:-}"
RECORD_TYPES="${RECORD_TYPES:-A,AAAA,CNAME,MX,TXT}"
VERBOSE="${VERBOSE:-false}"
SUBSCRIPTION="${SUBSCRIPTION:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Compare Azure private DNS zone records with public DNS records"
    echo ""
    echo "Options:"
    echo "  -g, --resource-group RG      Azure resource group containing private DNS zone"
    echo "  -z, --zone ZONE              Private DNS zone name"
    echo "  -s, --subscription SUB       Azure subscription ID (optional)"
    echo "  -t, --types TYPES            Record types to check (default: A,AAAA,CNAME,MX,TXT)"
    echo "  -v, --verbose                Verbose output"
    echo "  -h, --help                   Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  RESOURCE_GROUP               Azure resource group"
    echo "  PRIVATE_ZONE                 Private DNS zone name"
    echo "  SUBSCRIPTION                 Azure subscription ID"
    echo "  RECORD_TYPES                 Comma-separated record types"
    echo "  VERBOSE                      Set to 'true' for verbose output"
    echo ""
    echo "Examples:"
    echo "  $0 -g myResourceGroup -z example.com"
    echo "  $0 -g myRG -z example.com -t A,CNAME -v"
    exit 1
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

normalize_record() {
    local input
    input=$(cat)
    if [[ -z "$input" ]]; then
        echo "Error: normalize_record received empty input" >&2
        return 1
    fi
    echo "$input" | tr '[:upper:]' '[:lower:]' | sed 's/\.$//g' | sort
}

get_private_records() {
    local zone="$1"
    local record_name="$2"
    local type="$3"
    local rg="$4"

    log_verbose "Getting $type records for $record_name from private zone $zone"

    local cmd="az network private-dns record-set"

    case "$type" in
        "A")
            cmd+=" a show --zone-name $zone --resource-group $rg --name $record_name --query 'aRecords[].ipv4Address' -o tsv 2>/dev/null || echo ''"
            ;;
        "AAAA")
            cmd+=" aaaa show --zone-name $zone --resource-group $rg --name $record_name --query 'aaaaRecords[].ipv6Address' -o tsv 2>/dev/null || echo ''"
            ;;
        "CNAME")
            cmd+=" cname show --zone-name $zone --resource-group $rg --name $record_name --query 'cnameRecord.cname' -o tsv 2>/dev/null || echo ''"
            ;;
        "MX")
            cmd+=" mx show --zone-name $zone --resource-group $rg --name $record_name --query 'mxRecords[].[preference, exchange]' -o tsv 2>/dev/null | sed 's/\t/ /' || echo ''"
            ;;
        "TXT")
            cmd+=" txt show --zone-name $zone --resource-group $rg --name $record_name --query 'txtRecords[].value[]' -o tsv 2>/dev/null || echo ''"
            ;;
        *)
            echo ""
            return
            ;;
    esac

    if [[ -n "$SUBSCRIPTION" ]]; then
        cmd="az account set --subscription $SUBSCRIPTION && $cmd"
    fi

    eval "$cmd"
}

get_public_records() {
    local domain="$1"
    local type="$2"

    log_verbose "Getting $type records for $domain from public DNS"

    local result
    result=$(dig +short +time=5 +tries=2 @8.8.8.8 "$domain" "$type" 2>/dev/null) || true

    case "$type" in
        A)
            echo "$result" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true
            ;;
        AAAA)
            echo "$result" | grep -E '^[0-9a-f:]+$' || true
            ;;
        *)
            echo "$result"
            ;;
    esac
}

list_private_records() {
    local zone="$1"
    local rg="$2"

    log_verbose "Listing all records in private zone $zone"

    local cmd="az network private-dns record-set list --zone-name $zone --resource-group $rg --query '[].{name:name,type:type}' -o tsv"

    if [[ -n "$SUBSCRIPTION" ]]; then
        cmd="az account set --subscription $SUBSCRIPTION && $cmd"
    fi

    eval "$cmd"
}

compare_records() {
    local zone="$1"
    local record_name="$2"
    local type="$3"
    local rg="$4"

    local full_domain="$record_name"
    if [[ "$record_name" != "@" ]]; then
        if [[ "$record_name" == "" || "$record_name" == "." ]]; then
            full_domain="$zone"
        else
            full_domain="$record_name.$zone"
        fi
    else
        full_domain="$zone"
    fi

    local private_records=$(get_private_records "$zone" "$record_name" "$type" "$rg")
    local public_records=$(get_public_records "$full_domain" "$type")

    local private_normalized=""
    local public_normalized=""

    if [[ -n "$private_records" ]]; then
        private_normalized=$(echo "$private_records" | normalize_record)
    fi

    if [[ -n "$public_records" ]]; then
        public_normalized=$(echo "$public_records" | normalize_record)
    fi

    log_verbose "Private: $private_normalized | Public: $public_normalized"

    # Format domain name for consistent width
    local formatted_domain=$(printf "%-40s" "$full_domain")

    if [[ -z "$private_records" && -z "$public_records" ]]; then
        echo -e "${BLUE}$formatted_domain $type   No records found${NC}"
        return
    fi

    if [[ -z "$private_records" ]]; then
        echo -e "${RED}$formatted_domain $type   ❌ Missing in private (Public: $public_records)${NC}"
        return
    fi

    if [[ -z "$public_records" ]]; then
        echo -e "${RED}$formatted_domain $type   ❌ Missing in public (Private: $private_records)${NC}"
        return
    fi

    if [[ "$private_normalized" == "$public_normalized" ]]; then
        echo -e "${GREEN}$formatted_domain $type   ✅ Match ($private_records)${NC}"
    else
        echo -e "${RED}$formatted_domain $type   ❌ Differ (Private: $private_records | Public: $public_records)${NC}"
    fi
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -z|--zone)
            PRIVATE_ZONE="$2"
            shift 2
            ;;
        -s|--subscription)
            SUBSCRIPTION="$2"
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

if [[ -z "$RESOURCE_GROUP" ]]; then
    echo "Error: Resource group is required"
    usage
fi

if [[ -z "$PRIVATE_ZONE" ]]; then
    echo "Error: Private DNS zone is required"
    usage
fi

if ! command -v az >/dev/null 2>&1; then
    echo "Error: Azure CLI not found. Please install Azure CLI."
    exit 1
fi

if ! command -v dig >/dev/null 2>&1; then
    echo "Error: 'dig' command not found. Please install bind-utils or dnsutils package."
    exit 1
fi

echo -e "${BLUE}Azure Private DNS Zone Comparison Tool${NC}"
echo "======================================"
echo "Resource Group: $RESOURCE_GROUP"
echo "Private Zone: $PRIVATE_ZONE"
if [[ -n "$SUBSCRIPTION" ]]; then
    echo "Subscription: $SUBSCRIPTION"
fi
echo "Record Types: $RECORD_TYPES"
echo ""

if [[ -n "$SUBSCRIPTION" ]]; then
    log_verbose "Setting Azure subscription to $SUBSCRIPTION"
    az account set --subscription "$SUBSCRIPTION" || {
        echo -e "${RED}Error: Failed to set subscription $SUBSCRIPTION${NC}"
        exit 1
    }
fi

log_verbose "Checking if private DNS zone exists"
if ! az network private-dns zone show --resource-group "$RESOURCE_GROUP" --name "$PRIVATE_ZONE" >/dev/null 2>&1; then
    echo -e "${RED}Error: Private DNS zone '$PRIVATE_ZONE' not found in resource group '$RESOURCE_GROUP'${NC}"
    exit 1
fi

echo "Getting all records from private zone..."
records=$(list_private_records "$PRIVATE_ZONE" "$RESOURCE_GROUP")

if [[ -z "$records" ]]; then
    echo -e "${YELLOW}No records found in private zone${NC}"
    exit 0
fi

IFS=',' read -ra types <<< "$RECORD_TYPES"

declare -A processed_records

while IFS=$'\t' read -r name type_full; do
    if [[ -z "$name" || -z "$type_full" ]]; then
        continue
    fi

    type=$(echo "$type_full" | sed 's/Microsoft.Network\/privateDnsZones\///')

    for check_type in "${types[@]}"; do
        check_type=$(echo "$check_type" | tr '[:lower:]' '[:upper:]' | xargs)

        if [[ "$type" == "$check_type" ]]; then
            record_key="${name}_${type}"

            if [[ -z "${processed_records[$record_key]:-}" ]]; then
                compare_records "$PRIVATE_ZONE" "$name" "$type" "$RESOURCE_GROUP"
                processed_records[$record_key]="1"
            fi
        fi
    done
done <<< "$records"

echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo -e "${GREEN}Green ✅${NC} = Records match between private and public zones"
echo -e "${RED}Red ❌${NC} = Records differ or missing in one zone"
echo -e "${BLUE}Blue ℹ️${NC} = Informational messages"