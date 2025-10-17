#!/bin/bash
set -e -x
HEALTH_ENDPOINT="http://localhost:3000/api/health"
API_BASE="http://$admin_user:$admin_password@localhost:3000/api"

USERNAME=`echo $1 | awk -F , '{print $1}'  | awk '{print $1}'`
PASSWORD=`echo $1 | awk -F , '{print $2}'  | awk '{print $1}'`
   EMAIL=`echo $1 | awk -F , '{print $3}'  | awk '{print $1}'`
DASHBOARDS=`echo $1 | awk -F , '{print $4}'  | awk '{print $1}'`
WRITE_PERM=2
echo $(date)
echo USERNAME:$USERNAME EMAIL:$EMAIL

# wait for grafana to become healthy
until $(curl --output /dev/null --silent --head --fail $HEALTH_ENDPOINT); do
    printf '.'
    sleep 5
done

# create user
RESP=$(curl --header "Content-Type: application/json" --request POST --data "{\"email\":\"$EMAIL\", \"login\":\"$USERNAME\", \"password\":\"$PASSWORD\"}" $API_BASE/admin/users)

echo $RESP

max_attempts=10
sleep_duration=10

# Try to parse the created user id from the user creation curl response
regex='"id":([0-9]+)'
if [[ $RESP =~ $regex ]]; then
    # The captured group is stored in the BASH_REMATCH array
    id="$${BASH_REMATCH[1]}"
    echo "id is: $id"
    if [ -z "$DASHBOARDS" ]
    then
        echo "DASHBOARDS is empty"
    else
        echo "DASHBOARDS is NOT empty"
        IFS=':' read -ra ARR <<< "$DASHBOARDS"
        for DASHBOARD in "$${ARR[@]}"; do
            skipped="false"
            echo DASHBOARD:"$DASHBOARD"
            attempt=1
            # try to retrieve dashboard's permissions
            # $max_attempts retries max with $sleep_duration sleep between retries
            while [ $attempt -le $max_attempts ]; do
                response=$(curl -w "%{http_code}" "$API_BASE/dashboards/uid/$DASHBOARD/permissions" )
                STATUS_CODE=$${response:(-3)}
                if [ "$STATUS_CODE" -eq 200 ]; then
                    echo "URL returned 200 OK"
                    PERMS=$${response:0:-3}
                    break
                else
                    echo "Attempt $attempt: URL returned $STATUS_CODE"
                    if [ $attempt -lt $max_attempts ]; then
                        echo "Sleeping for $sleep_duration seconds before next attempt..."
                        sleep $sleep_duration
                    else
                        echo "Max attempts reached. Skipping."
                        skipped="true"
                        break
                    fi
                fi
                ((attempt++))
            done
            if [ "$skipped" = "false" ]; then
                AUGMENTED_PERMS="{\"items\":$${PERMS::-1},{\"userId\":$id,\"permission\":$WRITE_PERM}]}"
                echo AUGMENTED_PERMS:$AUGMENTED_PERMS
                curl -X POST "$API_BASE/dashboards/uid/$DASHBOARD/permissions" -H 'Accept: application/json' -H 'Content-Type: application/json' -d "$AUGMENTED_PERMS"
                echo
            else
                echo "dashboard skipped!"
            fi
        done
    fi
else
    echo "cannot find id of created user."
fi

echo
