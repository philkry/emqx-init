FROM mainflux/cli as cli


FROM alpine
ENV TERM xterm-256color
RUN apk --no-cache add bash curl jq \
    && mkdir /data
COPY bootstrap_mainflux.sh /data/
COPY lib /data/lib/
COPY --from=cli /exe /data/mainflux-cli
ENTRYPOINT [ "/data/bootstrap_mainflux.sh" ]

