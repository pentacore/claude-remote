FROM docker:29-dind
RUN apk add --no-cache e2fsprogs e2fsprogs-extra jq curl tzdata
COPY entrypoint.sh /usr/local/bin/dind-entrypoint.sh
COPY janitor.sh /usr/local/bin/janitor.sh
COPY janitor-lib.sh /usr/local/lib/janitor-lib.sh
COPY crontab /etc/crontabs/root
RUN chmod 0755 /usr/local/bin/dind-entrypoint.sh /usr/local/bin/janitor.sh
ENV DIND_IMG=/dind/docker.img DIND_SIZE_GB=100 TZ=Europe/Stockholm \
    JANITOR_IDLE_MIN=120 JANITOR_MAX_AGE_MIN=1440 JANITOR_UNTAGGED_MAX_AGE_MIN=60 \
    JANITOR_MARKER_MAX_AGE_MIN=10080 JANITOR_SOFT_PCT=75 JANITOR_HARD_PCT=90
ENTRYPOINT ["/usr/local/bin/dind-entrypoint.sh"]
CMD []
