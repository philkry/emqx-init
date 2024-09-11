# Node-Red-EMQX-Init

This project provides a script to bootstrap EMQX with multiple users and their permissions for use with Node-RED.

## Required Environment Variables

| Name | Description | Default |
|------|-------------|---------|
| EMQX_HOST | EMQX Dashboard Host | emqx-dashboard.emqx.svc.cluster.local:18083 |
| EMQX_API_KEY | EMQX API Key | not set |
| EMQX_API_USER | EMQX API User | bootstrap_node_red |
| CHANNEL_ID | MQTT Channel ID | 3c78cf3f-d5b5-40ed-b851-bd86c2edaa52 |
| MQTT_USERS | Comma-separated list of MQTT users to create | node-red |
| &lt;USERNAME&gt;_PASSWORD | Password for each MQTT user (e.g., NODE_RED_PASSWORD) | not set |

## Usage

To use this script, set the required environment variables and run the `bootstrap_emqx.sh` script. For example:

```bash
export EMQX_API_KEY="your-api-key"
export MQTT_USERS="user1,user2,user3"
export USER1_PASSWORD="password1"
export USER2_PASSWORD="password2"
export USER3_PASSWORD="password3"
./bootstrap_emqx.sh
```

This will create the specified users with their respective passwords and grant them permissions to the MQTT topic.

## Using as an Init Container in Kubernetes

To use this container as an init container in a Kubernetes deployment, you can add it to your deployment specification. Here's an example:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: node-red
spec:
  replicas: 1
  selector:
    matchLabels:
      app: node-red
  template:
    metadata:
      labels:
        app: node-red
    spec:
      initContainers:
      - name: emqx-init
        image: your-docker-registry/node-red-emqx-init:latest
        env:
        - name: EMQX_HOST
          value: "emqx-dashboard.emqx.svc.cluster.local:18083"
        - name: EMQX_API_KEY
          valueFrom:
            secretKeyRef:
              name: emqx-secrets
              key: api-key
        - name: MQTT_USERS
          value: "node-red,sensor1,sensor2"
        - name: NODE_RED_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mqtt-secrets
              key: node-red-password
        - name: SENSOR1_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mqtt-secrets
              key: sensor1-password
        - name: SENSOR2_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mqtt-secrets
              key: sensor2-password
      containers:
      - name: node-red
        image: nodered/node-red:latest
        # ... rest of your Node-RED container specification
```

In this example:

1. The init container uses the image built from this project.
2. Environment variables are set, including the EMQX host and API key.
3. The MQTT users are specified in the `MQTT_USERS` environment variable.
4. Passwords for each user are stored in Kubernetes secrets and referenced in the environment variables.

Make sure to create the necessary secrets (`emqx-secrets` and `mqtt-secrets` in this example) before applying the deployment.

This init container will run before the main Node-RED container starts, ensuring that the required MQTT users are created and properly configured in EMQX.

## Building the Docker Image

To build the Docker image:

```bash
docker build -t your-docker-registry/node-red-emqx-init:latest .
```

Push the image to your Docker registry:

```bash
docker push your-docker-registry/node-red-emqx-init:latest
```

Replace `your-docker-registry` with the appropriate Docker registry for your environment.