FROM php:7-apache

RUN a2enmod headers && a2enmod remoteip

COPY download-dir.conf /etc/apache2/conf-enabled/download-dir.conf
COPY reverse-proxy.conf /etc/apache2/conf-enabled/reverse-proxy.conf
COPY php-errors.ini /usr/local/etc/php/conf.d/
COPY php-uploads.ini /usr/local/etc/php/conf.d/
COPY index.php /var/www/html/
RUN mkdir /var/www/dl && chown www-data:www-data /var/www/dl
VOLUME /var/www/dl
