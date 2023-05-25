FROM golang:1.19-alpine AS ci
ARG SVC
ARG GOARCH
ARG GOARM
ARG VERSION
ARG COMMIT
ARG TIME
ARG TARGETPLATFORM

WORKDIR /go/src/github.com/mainflux/mainflux
COPY . .
RUN apk update \
    && apk add make\
    && GOARCH=$(cut -c 7-11 $TARGETPLATFORM) make cli \
    && mv build/mainflux-cli /exe

FROM scratch
# Certificates are needed so that mailing util can work.
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=builder /exe /
ENTRYPOINT ["/exe"]


FROM alpine
ENV TERM xterm-256color
RUN apk --no-cache add bash curl jq \
    && mkdir /data
COPY bootstrap_mainflux.sh /data/
COPY lib /data/lib/
COPY --from=cli /exe /data/mainflux-cli
ENTRYPOINT [ "/data/bootstrap_mainflux.sh" ]

