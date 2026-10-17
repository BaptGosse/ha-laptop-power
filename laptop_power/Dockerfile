ARG BUILD_FROM
FROM $BUILD_FROM

# rtcwake schedules the wake-up through the RTC alarm
RUN apk add --no-cache util-linux-misc

COPY run.sh /
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
