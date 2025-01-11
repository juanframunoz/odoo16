#!/bin/bash

# =============================================================================
# Script para instalar Odoo 16 Community con localización española y tema
# similar al de Enterprise en Ubuntu 20.04 utilizando Docker y Docker Compose.
# Configura Nginx como proxy inverso y Let’s Encrypt SSL para el dominio:
#    odoo16.2pz.org
# =============================================================================

# === Variables de configuración ===
ODOO_VERSION="16.0"
ODOO_USER="odoo16"
ODOO_HOME="/opt/odoo16"
ODOO_DATA="$ODOO_HOME/data"
ODOO_ADDONS="$ODOO_HOME/custom-addons"
DOMAIN="odoo16.2pz.org"
EMAIL="admin@odoo16.2pz.org"  # Reemplaza con tu correo electrónico real
NGINX_CONF="/etc/nginx/sites-available/${DOMAIN}.conf"
CERTBOT_CHALLENGE="/var/www/certbot"

# === 1. Actualizar el sistema e instalar dependencias ===
echo "=========================================================="
echo "1. Actualizando el sistema e instalando dependencias"
echo "=========================================================="
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install -y \
    git \
    curl \
    wget \
    unzip \
    nginx \
    certbot \
    python3-certbot-nginx \
    docker.io \
    docker-compose

# Añadir el usuario actual al grupo docker (para usar docker sin sudo)
sudo usermod -aG docker $USER

# Reiniciar el servicio de Docker
sudo systemctl restart docker

# === 2. Verificar Instalación de Docker ===
echo "=========================================================="
echo "2. Verificando instalación de Docker"
echo "=========================================================="
if ! command -v docker &> /dev/null; then
    echo "Docker no se instaló correctamente. Abortando."
    exit 1
else
    echo "Docker está instalado correctamente."
fi

# === 3. Crear Directorios Necesarios ===
echo "=========================================================="
echo "3. Creando directorios necesarios"
echo "=========================================================="
sudo mkdir -p $ODOO_DATA $ODOO_ADDONS $CERTBOT_CHALLENGE
sudo chown -R $USER:$USER $ODOO_HOME
sudo chown -R www-data:www-data $CERTBOT_CHALLENGE

# === 4. Crear usuario de sistema para Odoo ===
echo "=========================================================="
echo "4. Creando usuario de sistema para Odoo"
echo "=========================================================="
if id "$ODOO_USER" &> /dev/null; then
    echo "El usuario $ODOO_USER ya existe. Continuando..."
else
    sudo adduser --system --quiet --group --home "$ODOO_HOME" "$ODOO_USER"
    echo "Usuario $ODOO_USER creado."
fi

# === 5. Crear archivo docker-compose.yml ===
echo "=========================================================="
echo "5. Creando archivo docker-compose.yml"
echo "=========================================================="
cat > $ODOO_HOME/docker-compose.yml <<EOF
version: '3.1'

services:

  db:
    image: postgres:13
    environment:
      - POSTGRES_DB=postgres
      - POSTGRES_USER=odoo16
      - POSTGRES_PASSWORD=odoo16password  # Cambia esto por una contraseña segura
    volumes:
      - db_data:/var/lib/postgresql/data
    restart: unless-stopped

  web:
    image: odoo:\$ODOO_VERSION
    depends_on:
      - db
    ports:
      - "8069:8069"
    environment:
      - HOST=db
      - USER=odoo16
      - PASSWORD=odoo16password  # Debe coincidir con POSTGRES_PASSWORD
    volumes:
      - ./addons:/mnt/extra-addons
      - ./data:/var/lib/odoo
    restart: unless-stopped

volumes:
  db_data:
EOF

# Cambiar permisos del archivo docker-compose.yml
sudo chown $USER:$USER $ODOO_HOME/docker-compose.yml

# === 6. Clonar Localización Española y Tema Cybrosys ===
echo "=========================================================="
echo "6. Clonando localización española y tema Cybrosys"
echo "=========================================================="
cd $ODOO_ADDONS

# Clonar localización española de OCA
git clone https://github.com/OCA/l10n-spain.git

# Clonar tema Cybrosys (que contiene el módulo backend_theme_cybrosys)
git clone --depth 1 --branch 16.0 https://github.com/CybroOdoo/CybroAddons.git

# === 7. Iniciar los Servicios de Docker Compose ===
echo "=========================================================="
echo "7. Iniciando servicios de Docker Compose"
echo "=========================================================="
cd $ODOO_HOME
docker-compose up -d

# Esperar unos segundos para que Odoo se inicie
echo "Esperando a que Odoo se inicie..."
sleep 20

# === 8. Configurar Nginx como Proxy Inverso con SSL ===
echo "=========================================================="
echo "8. Configurando Nginx como proxy inverso con SSL"
echo "=========================================================="

# Crear configuración de Nginx para Odoo
sudo tee $NGINX_CONF > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root $CERTBOT_CHALLENGE;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    client_max_body_size 200M;

    location / {
        proxy_pass http://localhost:8069;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Habilitar la configuración de Nginx
sudo ln -sf $NGINX_CONF /etc/nginx/sites-enabled/$DOMAIN.conf

# Crear directorio para desafíos de Certbot
sudo mkdir -p /var/www/certbot

# Verificar la configuración de Nginx y recargar
sudo nginx -t && sudo systemctl reload nginx

# === 9. Obtener Certificado SSL con Certbot ===
echo "=========================================================="
echo "9. Obteniendo certificado SSL con Certbot"
echo "=========================================================="
sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL

# Verificar la configuración de Nginx y recargar nuevamente
sudo nginx -t && sudo systemctl reload nginx

# === 10. Configurar Renovación Automática de Certificados ===
echo "=========================================================="
echo "10. Configurando renovación automática de certificados"
echo "=========================================================="
# Certbot ya instala una tarea cron o un timer de systemd para la renovación automática.

echo "=========================================================="
echo "¡Instalación y configuración de Odoo 16 completada!"
echo "=========================================================="
echo " - Accede a tu Odoo en https://$DOMAIN"
echo " - Usuario administrador: admin"
echo " - Contraseña maestra: revisa la configuración en docker-compose.yml y los parámetros de Odoo"
echo " - Para gestionar Odoo, navega al directorio $ODOO_HOME y usa docker-compose."
echo "=========================================================="
