#!/usr/bin/env bash

# Set the script execution environment
TERM=xterm-256color

# Import necessary libraries
source "$(cd "${BASH_SOURCE[0]%/*}" && pwd)/lib/oo-bootstrap.sh"
import util/log util/exception util/tryCatch

# Set the log output
namespace mainfluxBootstrap
Log::AddOutput mainfluxBootstrap STDERR
set -x
# Define the Mainflux hosts and other variables
MAINFLUX_THINGS_HOST="${MAINFLUX_THINGS_HOST:-mainflux-things.mf.svc.cluster.local:8182}"
MAINFLUX_USERS_HOST="${MAINFLUX_USERS_HOST:-mainflux-users.mf.svc.cluster.local:8180}"
MAINFLUX_BOOTSTRAP_HOST="${MAINFLUX_BOOTSTRAP_HOST:-mainflux-bootstrap.mf.svc.cluster.local:8182}"
ENV_FILE="${ENV_FILE:-/data/env/.env}"
BINARY="/data/mainflux-cli"

try {
    # Retrieve the JWT token
    TOKEN=$($BINARY -m "http:/" -t "$MAINFLUX_THINGS_HOST" -u "$MAINFLUX_USERS_HOST" --raw users token "$MAINFLUX_USER" "$MAINFLUX_PASSWORD" || { e="Failed to retrieve JWT!"; throw; })

    # Check if the channel exists
    CHANNELS=$($BINARY -m "http:/" -t "$MAINFLUX_THINGS_HOST" -u "$MAINFLUX_USERS_HOST" --raw channels get all -n "$MAINFLUX_USER" "$TOKEN" || { e="Failed to retrieve channel list!"; throw; })
    if [ -n "$CHANNELS" ] && [ "$(echo "$CHANNELS" | jq '.total')" -gt 0 ]; then
        # Channel exists
        CHANNEL_ID=$(echo "$CHANNELS" | jq --raw-output '.channels[0].id')
        Log "Channel found with ID $CHANNEL_ID"
    else
        # Channel does not exist, create it
        Log "No channel found. Creating..."
        JSON_STRING='{"name":"'"$MAINFLUX_USER"'"}'
        CHANNEL_ID=$($BINARY -m "http:/" -t "$MAINFLUX_THINGS_HOST" -u "$MAINFLUX_USERS_HOST" --raw channels create "$JSON_STRING" "$TOKEN")
        Log "$(UI.Color.Green)Channel created with ID $CHANNEL_ID$(UI.Color.Default)"
    fi

    # Check if the bootstrap configuration exists
    BOOTSTRAP_CONFIG=$(curl -s --request GET "$MAINFLUX_BOOTSTRAP_HOST/things/configs?name=node-red" --header "Authorization: $TOKEN")
    if [ "$BOOTSTRAP_CONFIG" != "null" ] && [ "$(echo "$BOOTSTRAP_CONFIG" | jq '.total')" -eq 1 ]; then
        # Config exists
        MQTT_USER=$(echo "$BOOTSTRAP_CONFIG" | jq --raw-output '.configs[0].mainflux_id')
        MQTT_PASSWORD=$(echo "$BOOTSTRAP_CONFIG" | jq --raw-output '.configs[0].mainflux_key')
        Log "MQTT user is $MQTT_USER"
    else
        # Config does not exist, create it
        Log "No bootstrap config found. Creating..."
        BS_JSON_STRING=$(jq -n \
            --arg ek "$EXTERNAL_KEY" \
            --arg ei "node-red" \
            --arg ch "$CHANNEL_ID" \
            --arg na "node-red" \
            '{external_id: $ei, external_key: $ek, name: $na, channels: [ $ch ]}')
        curl -s --request POST "$MAINFLUX_BOOTSTRAP_HOST/things/configs" \
            --header "Authorization: $TOKEN" \
            --header 'Content-Type: application/json' \
            --data-raw "$BS_JSON_STRING"
        sleep 2
        BOOTSTRAP_DATA=$(curl -s --request GET "$MAINFLUX_BOOTSTRAP_HOST/things/bootstrap/node-red" --header "Authorization: $TOKEN")
        MQTT_USER=$(echo "$BOOTSTRAP_DATA" | jq --raw-output '.mainflux_id')
        MQTT_PASSWORD=$(echo "$BOOTSTRAP_DATA" | jq --raw-output '.mainflux_key')
        CHANNEL_ID=$(echo "$BOOTSTRAP_DATA" | jq --raw-output '.mainflux_channels[0].id')
        Log "$(UI.Color.Green)MQTT user is $MQTT_USER$(UI.Color.Default)"
        Log "Connecting Thing to Channel"
        # Uncomment the following line if you want to connect the Thing to the channel
        $BINARY -m "http:/" -t "$MAINFLUX_THINGS_HOST" -u "$MAINFLUX_USERS_HOST" --raw things connect "$MQTT_USER" "$CHANNEL_ID" "$TOKEN"
        Log "Activating user"
        curl -s --fail-with-body --request POST "$MAINFLUX_BOOTSTRAP_HOST/things/state/$MQTT_USER" \
            --header "Authorization: $TOKEN" \
            --header 'Content-Type: application/json' \
            -d '{"state": 1}'
    fi

    # Create the ENV file
    MQTT_ROOT_TOPIC="channels/$CHANNEL_ID/messages"
    Log "Creating ENV file"
    echo "MQTT_USER=$MQTT_USER" >"$ENV_FILE"
    echo "MQTT_PASSWORD=$MQTT_PASSWORD" >>"$ENV_FILE"
    echo "MQTT_ROOT_TOPIC=$MQTT_ROOT_TOPIC" >>"$ENV_FILE"
    echo "MQTT_TOPIC_TELE=$MQTT_ROOT_TOPIC/tele/#" >>"$ENV_FILE"
    echo "MQTT_TOPIC_STAT=$MQTT_ROOT_TOPIC/stat/#" >>"$ENV_FILE"
    echo "MQTT_TOPIC_CMND=$MQTT_ROOT_TOPIC/cmnd/" >>"$ENV_FILE"
} catch {
    Log "Could not bootstrap Node-Red Thing in Mainflux!"
    Log "Caught Exception:$(UI.Color.Red) $__BACKTRACE_COMMAND__ $(UI.Color.Default)"
    Log "File: $__BACKTRACE_SOURCE__, Line: $__BACKTRACE_LINE__"

    # Print the caught exception
    Exception::PrintException "${__EXCEPTION__[@]}"
    exit 1
}
