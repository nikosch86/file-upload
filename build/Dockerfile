FROM php:8.4-apache

RUN a2enmod headers && a2enmod remoteip

COPY download-dir.conf /etc/apache2/conf-enabled/download-dir.conf
COPY php-errors.ini /usr/local/etc/php/conf.d/
COPY php-uploads.ini /usr/local/etc/php/conf.d/
COPY index.php /var/www/html/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
RUN mkdir /var/www/dl && chown www-data:www-data /var/www/dl
VOLUME /var/www/dl

# reverse-proxy.conf is generated at startup from TRUSTED_PROXIES / DEFAULT_EXPIRY.
# Setting ENTRYPOINT resets the base image CMD, so it has to be restated here.
ENTRYPOINT ["/entrypoint.sh"]
CMD ["apache2-foreground"]
