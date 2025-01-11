#!/bin/bash

# Variables de configuración
read -p "Introduce el dominio para Odoo (ejemplo: odoo16.example.com): " DOMAIN
read -p "Introduce el email para Let's Encrypt: " EMAIL

ODOO_VERSION="16.0"
ODOO_DB_USER="odoo"
ODOO_DB_PASSWORD="odoo"
ODOO_DB_PORT="5432"
PROJECT_DIR="/home/$USER/odoo16"
SESSION_DIR="odoo_sessions"
ODOO_USER="odoo16"

# Actualizar el sistema e instalar Docker y Docker Compose
sudo apt update && sudo apt upgrade -y
sudo apt install -y docker.io docker-compose
sudo systemctl enable docker
sudo systemctl start docker

# Crear usuario odoo16 si no existe
if ! id -u $ODOO_USER >/dev/null 2>&1; then
    sudo useradd -m -s /bin/bash $ODOO_USER
fi

# Crear directorios necesarios
mkdir -p $PROJECT_DIR/{addons,data,$SESSION_DIR}

# Asignar permisos
sudo chown -R $ODOO_USER:$ODOO_USER $PROJECT_DIR
chmod -R 777 $PROJECT_DIR

# Clonar localización española de OCA
sudo -u $ODOO_USER git clone --depth=1 https://github.com/OCA/l10n-spain.git $PROJECT_DIR/addons/l10n-spain

# Crear archivo docker-compose.yml
cat <<EOF > $PROJECT_DIR/docker-compose.yml
version: '3.1'

services:
  db:
    image: postgres:13
    container_name: odoo16_db
    environment:
      - POSTGRES_DB=postgres
      - POSTGRES_USER=$ODOO_DB_USER
      - POSTGRES_PASSWORD=$ODOO_DB_PASSWORD
    volumes:
      - db_data:/var/lib/postgresql/data
    networks:
      - odoo_network
    restart: unless-stopped

  web:
    image: odoo:$ODOO_VERSION
    container_name: odoo16_web
    depends_on:
      - db
    ports:
      - "8069:8069"
    environment:
      - HOST=db
      - USER=$ODOO_DB_USER
      - PASSWORD=$ODOO_DB_PASSWORD
      - DB_PORT=$ODOO_DB_PORT
    volumes:
      - ./addons:/mnt/extra-addons
      - ./data:/var/lib/odoo
      - ./$SESSION_DIR:/var/lib/odoo/sessions
    networks:
      - odoo_network
    restart: unless-stopped

  nginx:
    image: nginx:latest
    container_name: odoo16_nginx
    depends_on:
      - web
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf
      - certbot_certs:/etc/letsencrypt
      - certbot_logs:/var/log/letsencrypt
    networks:
      - odoo_network
    restart: unless-stopped

volumes:
  db_data:
  certbot_certs:
  certbot_logs:

networks:
  odoo_network:
    driver: bridge
EOF

# Crear archivo nginx.conf
cat <<EOF > $PROJECT_DIR/nginx.conf
server {
    server_name $DOMAIN www.$DOMAIN;

    location / {
        proxy_pass http://web:8069;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }

    listen 443 ssl;
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
}

server {
    if (\$host = $DOMAIN) {
        return 301 https://\$host\$request_uri;
    } # managed by Certbot

    if (\$host = www.$DOMAIN) {
        return 301 https://$DOMAIN\$request_uri;
    } # managed by Certbot

    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    return 404; # managed by Certbot
}
EOF

# Ir al directorio del proyecto
cd $PROJECT_DIR

# Levantar los contenedores
docker-compose up -d

# Solicitar certificado con Certbot
sudo docker run --rm \
  -v $PROJECT_DIR/certbot_certs:/etc/letsencrypt \
  -v $PROJECT_DIR/certbot_logs:/var/log/letsencrypt \
  certbot/certbot certonly --standalone \
  -d $DOMAIN -d www.$DOMAIN --non-interactive --agree-tos -m $EMAIL

# Reiniciar nginx para usar el certificado
docker-compose restart nginx

# Confirmación final
echo "Instalación completa. Accede a https://$DOMAIN o https://www.$DOMAIN para verificar la instalación de Odoo 16 con SSL."
