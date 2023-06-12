FROM alpine/httpie
ENV TERM xterm-256color

# Set the working directory
WORKDIR /data    

COPY bootstrap_emqx.sh .
COPY lib ./lib/

ENTRYPOINT [ "./bootstrap_emqx.sh" ]

