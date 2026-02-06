#!/bin/bash
set -euo pipefail

# -------------------------------------------------------
# sql_storage_audit.sh
# Enumerates all enabled subscriptions, lists Azure SQL
# databases, and reports actual used storage in GB via
# Azure Monitor metrics.
# -------------------------------------------------------

TMPFILE=$(mktemp)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_FILE="$SCRIPT_DIR/sql_storage_audit_$(date +%Y%m%d_%H%M%S).txt"
exec > >(tee "$OUTPUT_FILE")
trap 'rm -f "$TMPFILE"; echo ""; echo "Output saved to: $OUTPUT_FILE"' EXIT

print_header() {
    printf "%-30s %-22s %-30s %10s %10s %-18s\n" \
        "SUBSCRIPTION" "SERVER" "DATABASE" "MAX GB" "USED GB" "TIER"
    printf '%0.s-' {1..122}; echo
}

echo "Azure SQL Database Storage Audit"
echo "================================="

if ! az account show &>/dev/null; then
    echo "Not authenticated. Run 'az login'."
    exit 1
fi

echo "Fetching subscriptions..."
SUBSCRIPTIONS=$(az account list --query '[?state==`Enabled`].{id:id, name:name}' -o json)
SUB_COUNT=$(echo "$SUBSCRIPTIONS" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
echo "Found $SUB_COUNT enabled subscription(s)."
echo ""
print_header

for i in $(seq 0 $((SUB_COUNT - 1))); do
    SUB_ID=$(echo   "$SUBSCRIPTIONS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$i]['id'])")
    SUB_NAME=$(echo "$SUBSCRIPTIONS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$i]['name'])")

    az account set --subscription "$SUB_ID" 2>/dev/null

    SERVERS=$(az sql server list \
        --query '[].{name:name, rg:resourceGroup}' -o json 2>/dev/null || echo "[]")
    SERVER_COUNT=$(echo "$SERVERS" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")

    [[ "$SERVER_COUNT" -eq 0 ]] && continue

    for j in $(seq 0 $((SERVER_COUNT - 1))); do
        SERVER_NAME=$(echo "$SERVERS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$j]['name'])")
        SERVER_RG=$(echo   "$SERVERS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$j]['rg'])")

        DBS=$(az sql db list \
            --server "$SERVER_NAME" \
            --resource-group "$SERVER_RG" \
            --query "[?name!='master'].{name:name, maxBytes:maxSizeBytes, tier:sku.tier, id:id}" \
            -o json 2>/dev/null || echo "[]")
        DB_COUNT=$(echo "$DBS" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")

        [[ "$DB_COUNT" -eq 0 ]] && continue

        for k in $(seq 0 $((DB_COUNT - 1))); do
            DB_NAME=$(echo  "$DBS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$k]['name'])")
            MAX_BYTES=$(echo "$DBS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$k]['maxBytes'] or 0)")
            TIER=$(echo     "$DBS" | python3 -c "import sys,json; d=json.load(sys.stdin); v=d[$k].get('tier'); print(v if v else 'N/A')")
            DB_ID=$(echo    "$DBS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$k]['id'])")

            # Actual used space from Azure Monitor (storage metric, bytes)
            # 24h window + max_by to find the last non-null maximum value
            END_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
            START_TIME=$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)
            USED_BYTES=$(az monitor metrics list \
                --resource "$DB_ID" \
                --metric "storage" \
                --start-time "$START_TIME" \
                --end-time "$END_TIME" \
                --interval PT1H \
                --aggregation Maximum \
                --query 'max_by(value[0].timeseries[0].data, &maximum).maximum' \
                -o tsv 2>/dev/null || echo "")

            [[ -z "$USED_BYTES" || "$USED_BYTES" == "None" ]] && USED_BYTES=0

            MAX_GB=$(python3   -c "print(round($MAX_BYTES / 1073741824, 2))")
            USED_GB=$(python3  -c "print(round(float('$USED_BYTES') / 1073741824, 2))")

            # Accumulate totals
            echo "$MAX_BYTES $USED_BYTES" >> "$TMPFILE"

            printf "%-30s %-22s %-30s %10s %10s %-18s\n" \
                "${SUB_NAME:0:29}" \
                "${SERVER_NAME:0:21}" \
                "${DB_NAME:0:29}" \
                "$MAX_GB" \
                "$USED_GB" \
                "$TIER"
        done
    done
done

echo ""
echo "---"
python3 -c "
total_max = total_used = count = 0
try:
    with open('$TMPFILE') as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) == 2:
                total_max  += int(parts[0])
                total_used += float(parts[1])
                count += 1
except Exception:
    pass
print(f'Total databases  : {count}')
print(f'Total allocated  : {round(total_max  / 1073741824, 2)} GB')
print(f'Total used       : {round(total_used / 1073741824, 2)} GB')
"
