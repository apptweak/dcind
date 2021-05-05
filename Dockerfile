# Inspired by https://github.com/mumoshu/dcind
FROM alpine

ENV DOCKER_VERSION=19.03.12 \
    DOCKER_COMPOSE_VERSION=1.25.4

# Install Docker and Docker Compose and dependencies
RUN apk --no-cache add	\
		bash			\
		curl			\
		docker			\
		docker-compose	\
		jq			 && \
    rm -rf /root/.cache

# Include functions to start/stop docker daemon
COPY docker-lib.sh entrypoint.sh setup /

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/bash"]
