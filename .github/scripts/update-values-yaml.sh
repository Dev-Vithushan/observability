#!/bin/bash

# Script to update values.yaml with new Azure subscriptions
# Updates both AZURE_SERVICEDISCOVERY_SUBSCRIPTION_ID and amr_subscriptions

set -euo pipefail

VALUES_FILE="components/exporters/azure-metrics-exporter/values.yaml"
NEW_SUBS_FILE="/tmp/new_subscriptions.txt"

# Validate input file exists and has content
if [[ ! -f "$NEW_SUBS_FILE" ]] || [[ ! -s "$NEW_SUBS_FILE" ]]; then
    echo "ℹ️  No new subscriptions to process"
    exit 0
fi

# Read and normalize subscription IDs (one per line, sorted, unique)
NEW_SUBS=$(cat "$NEW_SUBS_FILE" | tr ',' '\n' | tr -d ' ' | grep -v '^$' | sort -u)

if [[ -z "$NEW_SUBS" ]]; then
    echo "ℹ️  No valid subscriptions found"
    exit 0
fi

echo "📋 New subscriptions to check:"
echo "$NEW_SUBS"
echo ""

# Backup original file
cp "$VALUES_FILE" "${VALUES_FILE}.backup"

CHANGES_MADE=false

# ============================================================================
# Update AZURE_SERVICEDISCOVERY_SUBSCRIPTION_ID (comma-separated string)
# ============================================================================
echo "🔍 Checking AZURE_SERVICEDISCOVERY_SUBSCRIPTION_ID..."
DISCOVERY_LINE=$(grep -n "AZURE_SERVICEDISCOVERY_SUBSCRIPTION_ID:" "$VALUES_FILE" | cut -d: -f1)

if [[ -n "$DISCOVERY_LINE" ]]; then
    CURRENT_CSV=$(sed -n "${DISCOVERY_LINE}p" "$VALUES_FILE" | sed 's/.*: "\(.*\)".*/\1/')
    
    # Split current CSV into array
    IFS=',' read -ra EXISTING_SUBS <<< "$CURRENT_CSV"
    
    # Add new subscriptions that don't exist
    NEW_ADDED=()
    while IFS= read -r sub; do
        if ! echo ",${CURRENT_CSV}," | grep -q ",${sub},"; then
            echo "  ➕ Adding $sub"
            EXISTING_SUBS+=("$sub")
            NEW_ADDED+=("$sub")
            CHANGES_MADE=true
        else
            echo "  ✓ Already exists: $sub"
        fi
    done <<< "$NEW_SUBS"
    
    # Update the line if changes were made
    if [[ ${#NEW_ADDED[@]} -gt 0 ]]; then
        # Join array back to CSV
        NEW_CSV=$(IFS=,; echo "${EXISTING_SUBS[*]}")
        sed -i "${DISCOVERY_LINE}s|: \".*\"|: \"$NEW_CSV\"|" "$VALUES_FILE"
        echo "  ✅ Updated AZURE_SERVICEDISCOVERY_SUBSCRIPTION_ID"
    fi
fi

# ============================================================================
# Update amr_subscriptions (YAML array)
# ============================================================================
echo ""
echo "🔍 Checking amr_subscriptions..."

AMR_START=$(grep -n "^amr_subscriptions: &amr_subscriptions" "$VALUES_FILE" | cut -d: -f1)

if [[ -n "$AMR_START" ]]; then
    # Find end of amr_subscriptions block (look for next non-indented line or next top-level key)
    AMR_END=$(awk -v start="$AMR_START" '
        NR > start && /^  - / { last = NR }
        NR > start && last > 0 && /^[^ ]/ { if (last > 0 && !printed) { print last; printed=1 }; exit }
        END { if (last > 0 && !printed) print last }
    ' "$VALUES_FILE")
    
    if [[ -z "$AMR_END" ]]; then
        echo "  ⚠️  WARNING: Could not find end of amr_subscriptions block"
        AMR_END=$(wc -l < "$VALUES_FILE" | tr -d ' ')
    fi
    
    # Extract existing subscriptions from the block
    EXISTING_BLOCK=$(sed -n "${AMR_START},${AMR_END}p" "$VALUES_FILE")
    
    # Collect subscriptions to add
    TO_ADD=()
    while IFS= read -r sub; do
        if ! echo "$EXISTING_BLOCK" | grep -q "^  - ${sub}"; then
            echo "  ➕ Will add $sub"
            TO_ADD+=("$sub")
            CHANGES_MADE=true
        else
            echo "  ✓ Already exists: $sub"
        fi
    done <<< "$NEW_SUBS"
    
    # Add all new subscriptions
    if [[ ${#TO_ADD[@]} -gt 0 ]]; then
        # Check if there's a blank line after the last subscription and remove it BEFORE inserting
        NEXT_LINE=$((AMR_END + 1))
        HAS_BLANK_LINE=false
        if sed -n "${NEXT_LINE}p" "$VALUES_FILE" | grep -q '^[[:space:]]*$'; then
            HAS_BLANK_LINE=true
            # Remove the blank line now, before inserting new subscriptions
            sed -i "${NEXT_LINE}d" "$VALUES_FILE"
        fi
        
        # Insert new subscriptions directly after the last existing one (no blank line in between)
        INSERT_LINE=$AMR_END
        for sub in "${TO_ADD[@]}"; do
            # Insert with 2-space indentation to match YAML structure
            sed -i "${INSERT_LINE}a\\  - ${sub}" "$VALUES_FILE"
            INSERT_LINE=$((INSERT_LINE + 1))
        done
        
        # If there was a blank line originally, add it back after all subscriptions
        if [[ "$HAS_BLANK_LINE" == "true" ]]; then
            sed -i "${INSERT_LINE}a\\
" "$VALUES_FILE"
        fi
        
        echo "  ✅ Added ${#TO_ADD[@]} subscription(s) to amr_subscriptions"
    fi
fi

echo ""
if [[ "$CHANGES_MADE" == "true" ]]; then
    echo "✅ Changes applied to $VALUES_FILE"
    rm -f "${VALUES_FILE}.backup"
else
    echo "ℹ️  No changes needed - all subscriptions already present"
    # Restore from backup since no changes
    mv "${VALUES_FILE}.backup" "$VALUES_FILE"
fi

