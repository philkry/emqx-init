FROM python:3-alpine

ENV TERM xterm-256color

RUN apk add --no-cache bash \
  && python -m pip install --upgrade pip wheel httpie

# Set the working directory
WORKDIR /data    

COPY bootstrap_emqx.sh .
RUN chmod +x bootstrap_emqx.sh

ENTRYPOINT [ "./bootstrap_emqx.sh" ]
