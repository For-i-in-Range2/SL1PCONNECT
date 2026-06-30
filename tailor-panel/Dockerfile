# Corrections :
#   - PHP 8.3 (7.4 = EOL depuis novembre 2022)
#   - Utilisateur non-root (www-data uid 33)
#   - curl installe pour le healthcheck du compose

FROM php:8.3-apache

RUN apt-get update && apt-get install -y --no-install-recommends \
        libpq-dev \
        curl \
    && docker-php-ext-install pdo pdo_pgsql \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Passer Apache en utilisateur non-root (www-data = uid 33)
RUN sed -i 's/User ${APACHE_RUN_USER}/User www-data/' /etc/apache2/apache2.conf \
 && sed -i 's/Group ${APACHE_RUN_GROUP}/Group www-data/' /etc/apache2/apache2.conf

COPY --chown=www-data:www-data index.php /var/www/html/index.php

# Supprimer la page par defaut d'Apache
RUN rm -f /var/www/html/index.html

USER www-data

EXPOSE 80
