FROM php:7-apache

RUN echo 'Alias "/dl" "/var/www/dl"' > /etc/apache2/conf-enabled/download-dir.conf

COPY index.php /var/www/html/
RUN mkdir /var/www/dl && chown www-data:www-data /var/www/dl
VOLUME /var/www/dl
