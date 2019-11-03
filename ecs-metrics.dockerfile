ARG ALPINE_VERSION=3.10
FROM alpine:${ALPINE_VERSION}

ENV TZ=UTC0
COPY ecs-metrics.sh /
RUN chmod 555 /ecs-metrics.sh && \
    apk add --no-cache curl jq

HEALTHCHECK --interval=60s --timeout=10s --retries=2 \
    CMD [ "/ecs-metrics.sh" ]

CMD ["tail", "-f", "/dev/null"]
