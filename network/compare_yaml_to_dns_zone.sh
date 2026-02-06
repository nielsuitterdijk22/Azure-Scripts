#!/bin/bash

set -euo pipefail

YAML_FILE="${YAML_FILE:-}"
DNS_ZONE="${DNS_ZONE:-}"
RESOURCE_GROUP="${RESOURCE_GROUP:-}"
SUBSCRIPTION="${SUBSCRIPTION:-}"
VERBOSE="${VERBOSE:-false}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

MATCH_COUNT=0
MISMATCH_COUNT=0
MISSING_IN_AZURE=0
MISSING_IN_YAML=0

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Compare YAML DNS records against an Azure Private DNS zone"
    echo ""
    echo "Options:"
    echo "  -f, --file FILE              YAML file containing DNS records"
    echo "  -z, --zone ZONE              Azure Private DNS zone name"
    echo "  -g, --resource-group RG      Azure resource group containing Private DNS zone"
    echo "  -s, --subscription SUB       Azure subscription ID (optional)"
    echo "  -v, --verbose                Verbose output"
    echo "  -h, --help                   Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  YAML_FILE                    YAML file path"
    echo "  DNS_ZONE                     Azure Private DNS zone name"
    echo "  RESOURCE_GROUP               Azure resource group"
    echo "  SUBSCRIPTION                 Azure subscription ID"
    echo "  VERBOSE                      Set to 'true' for verbose output"
    echo ""
    echo "YAML format example:"
    echo "  A:"
    echo "    www: 10.0.0.1"
    echo "    api: 10.0.0.2"
    echo "  CNAME:"
    echo "    mail: mail.example.com"
    echo "  MX:"
    echo "    \"@\": \"10 mail.example.com\""
    echo "  TXT:"
    echo "    \"@\": \"v=spf1 include:example.com ~all\""
    echo ""
    echo "Examples:"
    echo "  $0 -f dns-records.yaml -z example.com -g myResourceGroup"
    echo "  $0 -f dns.yaml -z example.com -g myRG -s <subscription-id> -v"
    exit 1
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[MATCH]${NC} $1"
}

log_error() {
    echo -e "${RED}[DIFF]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

normalize_value() {
    local value="${1:-}"
    if [[ -n "$value" ]]; then
        echo "$value" | tr '[:upper:]' '[:lower:]' | sed 's/\.$//g' | xargs
    else
        echo ""
    fi
}

# Detect yq version and set appropriate command style
detect_yq_version() {
    if yq --version 2>&1 | grep -q "mikefarah"; then
        echo "mikefarah"
    elif yq --version 2>&1 | grep -q "kislyuk"; then
        echo "kislyuk"
    else
        # Try to detect based on behavior
        if yq -e '.' /dev/null 2>&1; then
            echo "mikefarah"
        else
            echo "kislyuk"
        fi
    fi
}

# Get record types from YAML (top-level keys like A, CNAME, MX, etc.)
get_yaml_record_types() {
    local yaml_file="$1"
    local yq_version="$2"

    if [[ "$yq_version" == "mikefarah" ]]; then
        yq eval 'keys | .[]' "$yaml_file" 2>/dev/null
    else
        yq -r 'keys | .[]' "$yaml_file" 2>/dev/null
    fi
}

# Get all record names for a given type
get_yaml_records_for_type() {
    local yaml_file="$1"
    local record_type="$2"
    local yq_version="$3"

    if [[ "$yq_version" == "mikefarah" ]]; then
        yq eval ".$record_type | keys | .[]" "$yaml_file" 2>/dev/null
    else
        yq -r ".$record_type | keys | .[]" "$yaml_file" 2>/dev/null
    fi
}

# Get value for a specific record
get_yaml_record_value() {
    local yaml_file="$1"
    local record_type="$2"
    local record_name="$3"
    local yq_version="$4"

    if [[ "$yq_version" == "mikefarah" ]]; then
        yq eval ".$record_type[\"$record_name\"]" "$yaml_file" 2>/dev/null
    else
        yq -r ".$record_type[\"$record_name\"]" "$yaml_file" 2>/dev/null
    fi
}

get_azure_record() {
    local zone="$1"
    local rg="$2"
    local name="$3"
    local type="$4"

    log_verbose "Getting Azure Private DNS record: $name ($type) from zone $zone"

    local type_lower=$(echo "$type" | tr '[:upper:]' '[:lower:]')
    local result=""

    case "$type_lower" in
        "a")
            result=$(az network private-dns record-set a show \
                --zone-name "$zone" \
                --resource-group "$rg" \
                --name "$name" \
                --query 'aRecords[].ipv4Address' \
                -o tsv 2>/dev/null | sort | tr '\n' ',' | sed 's/,$//' || echo "")
            ;;
        "aaaa")
            result=$(az network private-dns record-set aaaa show \
                --zone-name "$zone" \
                --resource-group "$rg" \
                --name "$name" \
                --query 'aaaaRecords[].ipv6Address' \
                -o tsv 2>/dev/null | sort | tr '\n' ',' | sed 's/,$//' || echo "")
            ;;
        "cname")
            result=$(az network private-dns record-set cname show \
                --zone-name "$zone" \
                --resource-group "$rg" \
                --name "$name" \
                --query 'cnameRecord.cname' \
                -o tsv 2>/dev/null || echo "")
            ;;
        "mx")
            result=$(az network private-dns record-set mx show \
                --zone-name "$zone" \
                --resource-group "$rg" \
                --name "$name" \
                --query 'mxRecords[].[preference, exchange]' \
                -o tsv 2>/dev/null | while read -r pref exch; do echo "$pref $exch"; done | sort | tr '\n' ',' | sed 's/,$//' || echo "")
            ;;
        "txt")
            result=$(az network private-dns record-set txt show \
                --zone-name "$zone" \
                --resource-group "$rg" \
                --name "$name" \
                --query 'txtRecords[].value[]' \
                -o tsv 2>/dev/null | sort | tr '\n' ',' | sed 's/,$//' || echo "")
            ;;
        "ptr")
            result=$(az network private-dns record-set ptr show \
                --zone-name "$zone" \
                --resource-group "$rg" \
                --name "$name" \
                --query 'ptrRecords[].ptrdname' \
                -o tsv 2>/dev/null | sort | tr '\n' ',' | sed 's/,$//' || echo "")
            ;;
        "srv")
            result=$(az network private-dns record-set srv show \
                --zone-name "$zone" \
                --resource-group "$rg" \
                --name "$name" \
                --query 'srvRecords[].[priority, weight, port, target]' \
                -o tsv 2>/dev/null | while read -r pri weight port target; do echo "$pri $weight $port $target"; done | sort | tr '\n' ',' | sed 's/,$//' || echo "")
            ;;
        *)
            log_warning "Unsupported record type: $type"
            return 1
            ;;
    esac

    echo "$result"
}

list_azure_records() {
    local zone="$1"
    local rg="$2"

    log_verbose "Listing all records from Azure Private DNS zone $zone"

    az network private-dns record-set list \
        --zone-name "$zone" \
        --resource-group "$rg" \
        --query '[].{name:name, type:type}' \
        -o tsv 2>/dev/null
}

compare_record() {
    local name="$1"
    local type="$2"
    local yaml_value="$3"
    local azure_value="$4"

    local yaml_normalized=$(normalize_value "$yaml_value")
    local azure_normalized=$(normalize_value "$azure_value")

    local formatted_name=$(printf "%-30s" "$name")
    local formatted_type=$(printf "%-6s" "$type")

    if [[ -z "$azure_value" ]]; then
        log_error "$formatted_name $formatted_type Missing in Azure (YAML: $yaml_value)"
        ((MISSING_IN_AZURE++)) || true
        return 1
    fi

    if [[ "$yaml_normalized" == "$azure_normalized" ]]; then
        log_success "$formatted_name $formatted_type Match ($yaml_value)"
        ((MATCH_COUNT++)) || true
        return 0
    else
        log_error "$formatted_name $formatted_type Differ"
        echo -e "         YAML:  $yaml_value"
        echo -e "         Azure: $azure_value"
        ((MISMATCH_COUNT++)) || true
        return 1
    fi
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--file)
            YAML_FILE="$2"
            shift 2
            ;;
        -z|--zone)
            DNS_ZONE="$2"
            shift 2
            ;;
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -s|--subscription)
            SUBSCRIPTION="$2"
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

if [[ -z "$YAML_FILE" ]]; then
    echo "Error: YAML file is required"
    usage
fi

if [[ -z "$DNS_ZONE" ]]; then
    echo "Error: DNS zone is required"
    usage
fi

if [[ -z "$RESOURCE_GROUP" ]]; then
    echo "Error: Resource group is required"
    usage
fi

if [[ ! -f "$YAML_FILE" ]]; then
    echo "Error: YAML file not found: $YAML_FILE"
    exit 1
fi

if ! command -v az >/dev/null 2>&1; then
    echo "Error: Azure CLI not found. Please install Azure CLI."
    exit 1
fi

if ! command -v yq >/dev/null 2>&1; then
    echo "Error: yq not found. Please install yq."
    exit 1
fi

YQ_VERSION=$(detect_yq_version)
log_verbose "Detected yq version: $YQ_VERSION"

echo -e "${BLUE}YAML to Azure Private DNS Zone Comparison Tool${NC}"
echo "==============================================="
echo "YAML File:        $YAML_FILE"
echo "Private DNS Zone: $DNS_ZONE"
echo "Resource Group:   $RESOURCE_GROUP"
if [[ -n "$SUBSCRIPTION" ]]; then
    echo "Subscription:     $SUBSCRIPTION"
fi
echo ""

if [[ -n "$SUBSCRIPTION" ]]; then
    log_verbose "Setting Azure subscription to $SUBSCRIPTION"
    az account set --subscription "$SUBSCRIPTION" || {
        echo -e "${RED}Error: Failed to set subscription $SUBSCRIPTION${NC}"
        exit 1
    }
fi

log_verbose "Checking if Private DNS zone exists"
if ! az network private-dns zone show --resource-group "$RESOURCE_GROUP" --name "$DNS_ZONE" >/dev/null 2>&1; then
    echo -e "${RED}Error: Private DNS zone '$DNS_ZONE' not found in resource group '$RESOURCE_GROUP'${NC}"
    exit 1
fi

# Build a lookup table of YAML records
declare -A yaml_records

echo -e "${BLUE}=== Comparing YAML records to Azure ===${NC}"
echo ""

record_types=$(get_yaml_record_types "$YAML_FILE" "$YQ_VERSION")

if [[ -z "$record_types" ]]; then
    echo -e "${RED}Error: No record types found in YAML file${NC}"
    exit 1
fi

for record_type in $record_types; do
    type_upper=$(echo "$record_type" | tr '[:lower:]' '[:upper:]')
    log_verbose "Processing record type: $type_upper"

    record_names=$(get_yaml_records_for_type "$YAML_FILE" "$record_type" "$YQ_VERSION")

    if [[ -z "$record_names" ]]; then
        log_verbose "No records found for type $type_upper"
        continue
    fi

    for record_name in $record_names; do
        yaml_value=$(get_yaml_record_value "$YAML_FILE" "$record_type" "$record_name" "$YQ_VERSION")

        if [[ -z "$yaml_value" || "$yaml_value" == "null" ]]; then
            log_warning "Skipping record with empty value: $record_name ($type_upper)"
            continue
        fi

        # Store in lookup table for reverse comparison
        yaml_records["${record_name}_${type_upper}"]="$yaml_value"

        azure_value=$(get_azure_record "$DNS_ZONE" "$RESOURCE_GROUP" "$record_name" "$type_upper" || echo "")
        compare_record "$record_name" "$type_upper" "$yaml_value" "$azure_value" || true
    done
done

echo ""
echo -e "${BLUE}=== Checking Azure records not in YAML ===${NC}"
echo ""

azure_records=$(list_azure_records "$DNS_ZONE" "$RESOURCE_GROUP")

while IFS=$'\t' read -r name type_full; do
    if [[ -z "$name" || -z "$type_full" ]]; then
        continue
    fi

    type=$(echo "$type_full" | sed 's/Microsoft.Network\/privateDnsZones\///')

    # Skip SOA records (always present in Azure)
    if [[ "$type" == "SOA" ]]; then
        log_verbose "Skipping SOA record"
        continue
    fi

    record_key="${name}_${type}"

    if [[ -z "${yaml_records[$record_key]:-}" ]]; then
        azure_value=$(get_azure_record "$DNS_ZONE" "$RESOURCE_GROUP" "$name" "$type" || echo "")
        formatted_name=$(printf "%-30s" "$name")
        formatted_type=$(printf "%-6s" "$type")
        log_warning "$formatted_name $formatted_type Exists in Azure but not in YAML ($azure_value)"
        ((MISSING_IN_YAML++)) || true
    fi
done <<< "$azure_records"

echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo "========================================"
echo -e "${GREEN}Matching records:          $MATCH_COUNT${NC}"
echo -e "${RED}Mismatched records:        $MISMATCH_COUNT${NC}"
echo -e "${RED}Missing in Azure:          $MISSING_IN_AZURE${NC}"
echo -e "${YELLOW}Missing in YAML:           $MISSING_IN_YAML${NC}"
echo "========================================"

total_issues=$((MISMATCH_COUNT + MISSING_IN_AZURE))
if [[ $total_issues -eq 0 && $MISSING_IN_YAML -eq 0 ]]; then
    echo -e "${GREEN}All records match!${NC}"
    exit 0
elif [[ $total_issues -eq 0 ]]; then
    echo -e "${YELLOW}YAML records match Azure, but Azure has extra records${NC}"
    exit 0
else
    echo -e "${RED}Found $total_issues issue(s) with YAML records${NC}"
    exit 1
fi
