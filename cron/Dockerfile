FROM alpine:3

RUN apk add bash dcron
RUN mkdir -p /var/logs

# 20 minute interval
ENV EXECUTION_CRON_EXPRESSION */20 * * * *

COPY entrypoint.sh /
COPY run-cron.sh /
RUN chmod +x /entrypoint.sh
RUN chmod +x /run-cron.sh
ENTRYPOINT ["/entrypoint.sh"]
