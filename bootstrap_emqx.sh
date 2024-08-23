#!/usr/bin/env bash

# Set the script execution environment
TERM=xterm-256color
set -x
# Define the Mainflux hosts and other variables
EMQX_HOST="${EMQX_HOST:-emqx-dashboard.emqx.svc.cluster.local:18083}"
EMQX_API_KEY="${EMQX_API_KEY}"
EMQX_API_USER="${EMQX_API_USER:-bootstrap_node_red}"
CHANNEL_ID="${CHANNEL_ID:-3c78cf3f-d5b5-40ed-b851-bd86c2edaa52}"
MQTT_USER="${MQTT_USER:-node-red}"
MQTT_PASSWORD="${MQTT_PASSWORD}"

ENV_FILE="${ENV_FILE:-/data/env/.env}"

create_env_file() {
    # Create the ENV file
    MQTT_ROOT_TOPIC="channels/$CHANNEL_ID/messages"
    echo "Creating ENV file"
    echo "MQTT_USER=$MQTT_USER" >"$ENV_FILE"
    echo "MQTT_PASSWORD=$MQTT_PASSWORD" >>"$ENV_FILE"
    echo "MQTT_ROOT_TOPIC=$MQTT_ROOT_TOPIC" >>"$ENV_FILE"
    echo "MQTT_TOPIC_TELE=$MQTT_ROOT_TOPIC/tele/#" >>"$ENV_FILE"
    echo "MQTT_TOPIC_STAT=$MQTT_ROOT_TOPIC/stat/#" >>"$ENV_FILE"
    echo "MQTT_TOPIC_CMND=$MQTT_ROOT_TOPIC/cmnd/" >>"$ENV_FILE"
}

create_authorization() {
    # Create authorization for the MQTT_TOPIC
    MQTT_TOPIC="channels/$CHANNEL_ID/messages"
    RESPONSE=$(http --ignore-stdin --auth "$EMQX_API_USER:$EMQX_API_KEY" POST "http://$EMQX_HOST/api/v5/authorization/sources/built_in_database/rules/users" \
        [0][username]=$MQTT_USER \
        [0][rules][0][action]=all \
        [0][rules][0][permission]=allow \
        [0][rules][0][topic]="$MQTT_TOPIC/#") 

    AUTH_STATUS=$(echo "$RESPONSE" | grep -o -m 1 '"code": "[^"]*' | cut -d'"' -f4 | tr '[:upper:]' '[:lower:]')

    if [[ $AUTH_STATUS == "success" || $AUTH_STATUS == "already_exists" ]]; then
        echo "Authorization for topic '$MQTT_TOPIC' created successfully."
    else
        ERROR_MSG=$(echo "$RESPONSE" | grep -o -m 1 '"error": "[^"]*' | cut -d'"' -f4)
        echo "Failed to create authorization: $ERROR_MSG"
        exit 1
    fi
}

# Step 1: Check if user 'node-red' exists
EXISTING_USER=$(http --auth "$EMQX_API_USER:$EMQX_API_KEY" --ignore-stdin --check-status GET "http://$EMQX_HOST/api/v5/authentication/password_based:built_in_database/users/node-red" &> /dev/null; echo $?)

if [[ $EXISTING_USER -eq 0 ]]; then
  echo "User 'node-red' already exists."
  create_env_file
  create_authorization
  exit 0
fi

# Step 2: Create user 'node-red'

RESPONSE=$(http --ignore-stdin --auth "$EMQX_API_USER:$EMQX_API_KEY" POST "http://$EMQX_HOST/api/v5/authentication/password_based:built_in_database/users" user_id=$MQTT_USER password=$MQTT_PASSWORD)

CREATION_STATUS=$(echo "$RESPONSE" | grep -o -m 1 '"status": "[^"]*' | cut -d'"' -f4)

if [[ $CREATION_STATUS == "success" ]]; then
  echo "User 'node-red' created successfully."
  create_env_file
  create_authorization
  exit 0
else
  ERROR_MSG=$(echo "$RESPONSE" | grep -o -m 1 '"error": "[^"]*' | cut -d'"' -f4)
  echo $ERROR_MSG
  exit 1
fi









