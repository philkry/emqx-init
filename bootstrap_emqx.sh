#!/usr/bin/env bash

# Set the script execution environment
TERM=xterm-256color
set -x

# Define the Mainflux hosts and other variables
EMQX_HOST="${EMQX_HOST:-emqx-dashboard.emqx.svc.cluster.local:18083}"
EMQX_API_KEY="${EMQX_API_KEY}"
EMQX_API_USER="${EMQX_API_USER:-bootstrap_node_red}"
CHANNEL_ID="${CHANNEL_ID:-3c78cf3f-d5b5-40ed-b851-bd86c2edaa52}"
MQTT_USERS="${MQTT_USERS:-node-red}" # Default to 'node-red' if not set
MQTT_TOPIC="channels/$CHANNEL_ID/messages"

create_authorization() {
    local username="$1"
    # Create authorization for the MQTT_TOPIC
    RESPONSE=$(http --ignore-stdin --auth "$EMQX_API_USER:$EMQX_API_KEY" POST "http://$EMQX_HOST/api/v5/authorization/sources/built_in_database/rules/users" \
        [0][username]="$username" \
        [0][rules][0][action]=all \
        [0][rules][0][permission]=allow \
        [0][rules][0][topic]="$MQTT_TOPIC/#") 

    AUTH_STATUS=$(echo "$RESPONSE" | grep -o -m 1 '"code":"[^"]*' | cut -d'"' -f4 | tr '[:upper:]' '[:lower:]')

    if [[ $AUTH_STATUS == "success" || $AUTH_STATUS == "already_exists" ]]; then
        echo "Authorization for user '$username' and topic '$MQTT_TOPIC' created successfully."
    else
        ERROR_MSG=$(echo "$RESPONSE" | grep -o -m 1 '"message":"[^"]*' | cut -d'"' -f4)
        echo "Failed to create authorization for user '$username': $ERROR_MSG"
    fi
}

create_user() {
    local username="$1"
    local password="$2"

    # Check if user exists
    EXISTING_USER=$(http --auth "$EMQX_API_USER:$EMQX_API_KEY" --ignore-stdin --check-status GET "http://$EMQX_HOST/api/v5/authentication/password_based:built_in_database/users/$username" &> /dev/null; echo $?)

    if [[ $EXISTING_USER -eq 0 ]]; then
        echo "User '$username' already exists."
    else
        # Create user
        RESPONSE=$(http --ignore-stdin --auth "$EMQX_API_USER:$EMQX_API_KEY" POST "http://$EMQX_HOST/api/v5/authentication/password_based:built_in_database/users" user_id="$username" password="$password")

        CREATION_STATUS=$(echo "$RESPONSE" | grep -o -m 1 '"status": "[^"]*' | cut -d'"' -f4)

        if [[ $CREATION_STATUS == "success" ]]; then
            echo "User '$username' created successfully."
        else
            ERROR_MSG=$(echo "$RESPONSE" | grep -o -m 1 '"error": "[^"]*' | cut -d'"' -f4)
            echo "Failed to create user '$username': $ERROR_MSG"
            return 1
        fi
    fi

    # Create authorization for the user
    create_authorization "$username"
}

# Main execution
IFS=',' read -ra USERS <<< "$MQTT_USERS"
for username in "${USERS[@]}"; do
    password_var="${username^^}_PASSWORD"
    password="${!password_var}"
    
    if [[ -z "$password" ]]; then
        echo "Error: Password not set for user $username. Please set ${password_var}."
        continue
    fi
    
    create_user "$username" "$password"
done
