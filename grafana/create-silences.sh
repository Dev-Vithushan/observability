#!/bin/sh

# Set basic auth credentials
USERNAME=$(cat /etc/creds/admin_user)
PASSWORD=$(cat /etc/creds/admin_password)
SILENCES_DIR="/etc/config"

# Set the silence creation failed flag to false
silence_creation_failed=false

# Set the URL to get and post the data
CREATE_GET_SILENCE_URL="http://localhost:3000/api/alertmanager/grafana/api/v2/silences"
DELETE_SILENCE_URL="http://localhost:3000/api/alertmanager/grafana/api/v2/silence"

# Initialize variables to store current and created silence IDs
created_silence_ids=""
current_silence_ids=""


while true; do
    STATUS="UNKNOWN"
    POD_NAME=$(hostname)
    NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
    STATUS=$(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.status.containerStatuses[?(@.name=="grafana")].state.waiting.reason}')
    if [ "$STATUS" != "" ]; then
        echo "Grafana container status: $STATUS"
        sleep 60
    else
        echo "Grafana container is running normally"
        break
    fi
done


# Get current silences ids
current_silences=$(curl -s -X GET -u "$USERNAME:$PASSWORD" "$CREATE_GET_SILENCE_URL")
current_silence_ids=$(echo "$current_silences" | jq -r '.[] | select(.status.state == "active") | .id')

# Build merged objects stream from all JSON files under the mounted directory
json_files=$(find "$SILENCES_DIR" -type f -name "*.json" 2>/dev/null | sort)
if [ -n "$json_files" ]; then
    # shellcheck disable=SC2086
    objects=$(jq -c -s 'add | .[]' $json_files)
else
    echo "No JSON files found in $SILENCES_DIR, will only clean up existing silences" >&2
    objects=""
fi

# Check if jq command was successful or if we have no objects to process
if [ $? -ne 0 ]; then
    silence_creation_failed=true
else
    if [ -n "$objects" ]; then
        echo "$objects" | while read -r object; do
            # Send a POST request with the object data
            response_body=$(curl -s -w "%{http_code}" -X POST -u "$USERNAME:$PASSWORD" -H "Content-Type: application/json" -d "$object" "$CREATE_GET_SILENCE_URL")
            creation_status_code=$(echo "$response_body" | tail -c 4 | head -c 3)
            response_body=$(echo "$response_body" | rev | cut -c 4- | rev)

            # Check if the response_body.txt file exists
            if [ "$creation_status_code" -ge 200 ] && [ "$creation_status_code" -lt 300 ]; then
                # Add the created silence ID to the list
                silenceID=$(echo "$response_body" | jq -r '.silenceID')
                created_silence_ids="$created_silence_ids $silenceID"
                echo "Created silence with ID: $silenceID successfully"
            else
                echo "Failed to create silence, Status Code: $creation_status_code, deleting created silences"
                silence_creation_failed=true
                for id in $created_silence_ids; do
                    # Perform the desired operation with the id
                    delete_status_code=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE -u "$USERNAME:$PASSWORD" -H "Content-Type: application/json" "$DELETE_SILENCE_URL/$id")
                    if [ "$delete_status_code" -ge 200 ] && [ "$delete_status_code" -lt 300 ]; then
                        echo "Deleted new silence with ID: $id"
                    else
                        echo "Failed to delete silence with ID: $id, Status Code: $delete_status_code"
                    fi
                done
                break
            fi
        done
    else
        echo "No silences to create, skipping creation step"
    fi
fi

# Check if the Status Code is in the 2xx range
if [ "$silence_creation_failed" = false ]; then
    echo "The creation of the silences was successful, deleting the old silences"
    if [ -z "$current_silence_ids" ]; then
        echo "No active silences found to delete"
    else
        # Loop through the ids and delete the old silences
        for id in $current_silence_ids; do
            # Perform the desired operation with the id
            delete_status_code=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE -u "$USERNAME:$PASSWORD" -H "Content-Type: application/json" "$DELETE_SILENCE_URL/$id")
            if [ "$delete_status_code" -ge 200 ] && [ "$delete_status_code" -lt 300 ]; then
                echo "Deleted previous silence with ID: $id"
            else
                echo "Failed to delete silence with ID: $id, Status Code: $delete_status_code"
            fi
        done
    fi
else
    echo "The creation of the silences failed"
fi
