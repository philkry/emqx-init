#!/usr/bin/env bash

# Set the script execution environment
TERM=xterm-256color
#set -x

# Define the Mainflux hosts and other variables
EMQX_HOST="${EMQX_HOST:-emqx-dashboard.emqx.svc.cluster.local:18083}"
EMQX_API_KEY="${EMQX_API_KEY}"
EMQX_API_USER="${EMQX_API_USER:-bootstrap_node_red}"
CHANNEL_ID="${CHANNEL_ID:-3c78cf3f-d5b5-40ed-b851-bd86c2edaa52}"
MQTT_USERS="${MQTT_USERS:-node-red}" # Default to 'node-red' if not set
MQTT_TOPIC="channels/$CHANNEL_ID/messages"
MAX_RETRIES="${MAX_RETRIES:-5}"
RETRY_DELAY="${RETRY_DELAY:-5}"
HTTP_TIMEOUT="${HTTP_TIMEOUT:-10}"

# Function to execute HTTP requests with retries
execute_request() {
    local command="$1"
    local retry_count=0
    local response=""
    local success=false

    while [ $retry_count -lt $MAX_RETRIES ] && [ "$success" = false ]; do
        if [ $retry_count -gt 0 ]; then
            echo "Retry attempt $retry_count after $RETRY_DELAY seconds..."
            sleep $RETRY_DELAY
        fi
        
        response=$(eval "$command" 2>&1)
        local status=$?
        
        if [ $status -eq 0 ] && [[ "$response" == *"HTTP/"* ]]; then
            success=true
        else
            echo "Request failed: $response"
            ((retry_count++))
        fi
    done
    
    if [ "$success" = false ]; then
        echo "Failed after $MAX_RETRIES attempts"
        echo "$response"
        return 1
    fi
    
    echo "$response"
    return 0
}

create_authorization() {
    local username="$1"
    # Create authorization for the MQTT_TOPIC
    echo "Creating authorization for user '$username' and topic '$MQTT_TOPIC'..."
    
    local cmd="http -h --ignore-stdin --timeout=$HTTP_TIMEOUT --auth \"$EMQX_API_USER:$EMQX_API_KEY\" POST \"http://$EMQX_HOST/api/v5/authorization/sources/built_in_database/rules/users\" [0][username]=\"$username\" [0][rules][0][action]=all [0][rules][0][permission]=allow [0][rules][0][topic]=\"$MQTT_TOPIC/#\""
    
    RESPONSE=$(execute_request "$cmd")
    if [ $? -ne 0 ]; then
        echo "Failed to create authorization for user '$username'"
        return 1
    fi

    HTTP_STATUS=$(echo "$RESPONSE" | head -n 1 | cut -d' ' -f2)

    if [[ $HTTP_STATUS -eq 200 || $HTTP_STATUS -eq 201 ]]; then
        echo "Authorization for user '$username' and topic '$MQTT_TOPIC' created successfully."
    else
        ERROR_MSG=$(echo "$RESPONSE" | grep -o -m 1 '"message":"[^"]*' | cut -d'"' -f4 || echo "Unknown error")
        echo "Failed to create authorization for user '$username': $ERROR_MSG"
        return 1
    fi
    
    # Add a short delay to avoid potential rate limiting
    sleep 1
}

create_user() {
    local username="$1"
    local password="$2"

    echo "Checking if user '$username' exists..."
    # Check if user exists
    local cmd="http -h --auth \"$EMQX_API_USER:$EMQX_API_KEY\" --timeout=$HTTP_TIMEOUT --ignore-stdin GET \"http://$EMQX_HOST/api/v5/authentication/password_based:built_in_database/users/$username\""
    
    RESPONSE=$(execute_request "$cmd")
    if [ $? -ne 0 ]; then
        echo "Failed to check if user '$username' exists"
        return 1
    fi
    
    HTTP_STATUS=$(echo "$RESPONSE" | head -n 1 | cut -d' ' -f2)

    if [[ $HTTP_STATUS -eq 200 ]]; then
        echo "User '$username' already exists."
    elif [[ $HTTP_STATUS -eq 404 ]]; then
        # Create user
        echo "Creating user '$username'..."
        local cmd="http -h --ignore-stdin --timeout=$HTTP_TIMEOUT --auth \"$EMQX_API_USER:$EMQX_API_KEY\" POST \"http://$EMQX_HOST/api/v5/authentication/password_based:built_in_database/users\" user_id=\"$username\" password=\"$password\""
        
        RESPONSE=$(execute_request "$cmd")
        if [ $? -ne 0 ]; then
            echo "Failed to create user '$username'"
            return 1
        fi
        
        HTTP_STATUS=$(echo "$RESPONSE" | head -n 1 | cut -d' ' -f2)

        if [[ $HTTP_STATUS -eq 201 ]]; then
            echo "User '$username' created successfully."
        else
            ERROR_MSG=$(echo "$RESPONSE" | grep -o -m 1 '"message":"[^"]*' | cut -d'"' -f4 || echo "Unknown error")
            echo "Failed to create user '$username': $ERROR_MSG"
            return 1
        fi
    else
        echo "Unexpected response when checking user '$username': HTTP $HTTP_STATUS"
        return 1
    fi

    # Add a short delay to avoid potential rate limiting
    sleep 1

    # Create authorization for the user
    create_authorization "$username"
}

# Check EMQX server availability before starting
echo "Checking connectivity to EMQX server at $EMQX_HOST..."
for i in $(seq 1 $MAX_RETRIES); do
    if http -h --timeout=$HTTP_TIMEOUT GET "http://$EMQX_HOST/api/v5/nodes" &>/dev/null; then
        echo "Successfully connected to EMQX server"
        break
    fi
    
    if [ $i -eq $MAX_RETRIES ]; then
        echo "Failed to connect to EMQX server after $MAX_RETRIES attempts. Exiting."
        exit 1
    fi
    
    echo "Attempt $i failed. Retrying in $RETRY_DELAY seconds..."
    sleep $RETRY_DELAY
done

# Main execution
echo "Starting user creation process..."
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

echo "EMQX bootstrap process completed."
