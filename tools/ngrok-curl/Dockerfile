FROM ngrok/ngrok:3.6.0-debian

USER root
RUN apt update && \
    apt upgrade -y && \
    apt-get install -y curl
USER ngrok

# podman push quay.io/hukhan/ngrok-curl:3.6.0-debian