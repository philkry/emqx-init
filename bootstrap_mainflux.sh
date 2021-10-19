#!/bin/bash
MAINFLUX_THINGS_HOST="${MAINFLUX_THINGS_HOST:-http://mainflux-things.mf.svc.cluster.local:8182}"
#MAINFLUX_THINGS_HOST="https://mainflux.k8s.h.kryno.de"
MAINFLUX_USERS_HOST="${MAINFLUX_USERS_HOST:-http://mainflux-users.mf.svc.cluster.local:8180}"
#MAINFLUX_USERS_HOST="https://mainflux.k8s.h.kryno.de"
MAINFLUX_BOOTSTRAP_HOST="${MAINFLUX_BOOTSTRAP_HOST:-http://mainflux-bootstrap.mf.svc.cluster.local:8182}"
#MAINFLUX_BOOTSTRAP_HOST="https://mainflux.k8s.h.kryno.de"
ENV_FILE="${ENV_FILE:-/data/env/.env}"
#ENV_FILE="/data/.env"
BINARY="/data/mainflux-cli"

TOKEN=$($BINARY -t $MAINFLUX_THINGS_HOST -u $MAINFLUX_USERS_HOST -r users token $MAINFLUX_USER $MAINFLUX_PASSWORD)
NODE_RED_THINGS=$($BINARY -t $MAINFLUX_THINGS_HOST -u $MAINFLUX_USERS_HOST -r things get all -n node-red $TOKEN)
NODE_RED_COUNT=$(echo $NODE_RED_THINGS | jq '.total')
CHANNELS=$($BINARY -t $MAINFLUX_THINGS_HOST -u $MAINFLUX_USERS_HOST -r channels get all -n $MAINFLUX_USER $TOKEN)
BOOTSTRAP_CONFIG=$(curl -s --location --request GET $MAINFLUX_BOOTSTRAP_HOST/things/configs?name=node-red --header "Authorization: ${TOKEN}")

if [  $(echo $CHANNELS | jq '.total') -eq 1 ]
then
    # Channel exists
    CHANNEL_ID=$(echo $CHANNELS | jq --raw-output '.channels[].id')
    echo "Channel found with ID ${CHANNEL_ID}"
else
    # Channel does not exist
    echo "No channel found. Creating..."
    JSON_STRING='{"name":"'"$MAINFLUX_USER"'"}'
    CHANNEL_ID=$($BINARY -t $MAINFLUX_THINGS_HOST -u $MAINFLUX_USERS_HOST -r channels create $JSON_STRING $TOKEN)
    echo "Channel created with ID ${CHANNEL_ID}"
fi

MQTT_TOPIC="channels/${CHANNEL_ID}/messages"

if [  $(echo $BOOTSTRAP_CONFIG | jq '.total') -eq 1 ]
then
    # Config exists
    MQTT_USER=$(echo $BOOTSTRAP_CONFIG | jq --raw-output '.configs[].mainflux_id')
    MQTT_PASSWORD=$(echo $BOOTSTRAP_CONFIG | jq --raw-output '.configs[].mainflux_key')
    echo "MQTT user is ${MQTT_USER}"
else
    # Config does not exist
    echo "No bootstrap config found. Creating..."
    BS_JSON_STRING='{"external_id": "node-red", "external_key":"'"$EXTERNAL_KEY"'", "name": "node-red", "channels": ""}'
    BS_JSON_STRING=$( jq -n \
                  --arg ek "$EXTERNAL_KEY" \
                  --arg ei "node-red" \
                  --arg ch "$CHANNEL_ID" \
                  --arg na "node-red" \
                  '{external_id: $ei, external_key: $ek, name: $na, channels: [ $ch ]}' )
    echo $BS_JSON_STRING
    curl -s --request POST $MAINFLUX_BOOTSTRAP_HOST/things/configs --header "Authorization: ${TOKEN}" --header 'Content-Type: application/json' -d "${BS_JSON_STRING}"
    BOOTSTRAP_CONFIG=$(curl -s --request GET $MAINFLUX_BOOTSTRAP_HOST/things/configs?name=node-red --header "Authorization: ${TOKEN}")
    MQTT_USER=$(echo $BOOTSTRAP_CONFIG | jq --raw-output '.configs[].mainflux_id')
    MQTT_PASSWORD=$(echo $BOOTSTRAP_CONFIG | jq --raw-output '.configs[].mainflux_key')
    echo "MQTT user is ${MQTT_USER}"  
    echo "Activating user"
    curl -s --request POST $MAINFLUX_BOOTSTRAP_HOST/things/state/$MQTT_USER --header "Authorization: ${TOKEN}" --header 'Content-Type: application/json' -d '{"state": 1}'  
fi

echo "Creating ENV file"
echo "MQTT_USER=${MQTT_USER}" > $ENV_FILE
echo "MQTT_PASSWORD=${MQTT_PASSWORD}" >> $ENV_FILE
echo "MQTT_TOPIC=${MQTT_TOPIC}" >> $ENV_FILE


