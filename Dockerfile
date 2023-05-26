FROM golang:1.19-alpine AS builder
ARG SVC
ARG GOARCH
ARG GOARM
ARG VERSION
ARG COMMIT
ARG TIME
ARG TARGETPLATFORM

# Set the working directory
WORKDIR /app

# Clone the Mainflux repository
RUN apk --no-cache add git
RUN git clone https://github.com/mainflux/mainflux.git .

# Build the Mainflux CLI service for AMD64
RUN CGO_ENABLED=0 GOARCH=amd64 go build -o mainflux-cli-amd64 ./cmd/cli

# Build the Mainflux CLI service for ARM64
RUN CGO_ENABLED=0 GOARCH=arm64 go build -o mainflux-cli-arm64 ./cmd/cli


FROM alpine
ENV TERM xterm-256color
RUN apk --no-cache add bash curl jq \
    && mkdir /data

# Set the working directory
WORKDIR /data    

# Copy the Mainflux CLI service based on the host architecture
COPY --from=builder /app/mainflux-cli-{{.TARGETPLATFORM}} ./mainflux-cli

COPY bootstrap_mainflux.sh .
COPY lib ./lib/

ENTRYPOINT [ "./bootstrap_mainflux.sh" ]

