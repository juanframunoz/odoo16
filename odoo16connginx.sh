#!/bin/bash

echo "Automatización de instalación de Odoo 16, Nginx y Let's Encrypt"
echo "-------------------------------------------------------------"

# Solicitar dominio y correo electrónico
read -p "Introduce tu dominio (ejemplo: tu-dominio.com): " dominio
read -p "Introduce tu correo electrónico (para Let's Encrypt): " email

if [ -z "$dominio" ] || [ -z "$email" ]; then
    echo "El dominio y el correo electrónico son obligatorios. Inténtalo de nuevo."
    exit 1
fi

# Actualizar sistema e instalar dependencias necesarias
echo "Actualizando sistema e instalando dependencias..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y git python3-pip build-essential wget python3-dev python3-venv python3-wheel \
libxslt-dev libzip-dev libldap2-dev libsasl2-dev python3-setuptools libjpeg-dev libpq-dev \
libxml2-dev libjpeg8-dev liblcms2-dev libblas-dev libatlas-base-dev libssl-dev libffi-dev \
postgresql postgresql-server-dev-all nodejs npm wkhtmltopdf nginx certbot python3-certbot-nginx

# Configurar PostgreSQL
echo "Configurando PostgreSQL..."
sudo -u postgres createuser --createdb --username postgres --no-createrole --no-superuser --pwprompt odoo

# Instalar y configurar Odoo 16
echo "Instalando Odoo 16..."
git clone https://www.github.com/odoo/odoo --branch 16.0 --depth 1 /opt/odoo
cd /opt/odoo
python3 -m venv odoo-venv
source odoo-venv/bin/activate
pip3 install wheel
pip3 install -r requirements.txt
deactivate

echo "Creando usuario y permisos para Odoo..."
sudo adduser --system --home=/opt/odoo --group odoo
sudo mkdir -p /opt/odoo/extra-addons /opt/odoo/.local
sudo chown -R odoo:odoo /opt/odoo
sudo chmod -R 755 /opt/odoo

echo "Creando archivo de configuración odoo.conf..."
sudo bash -c "cat > /etc/odoo.conf <<EOF
[options]
admin_passwd = odoo
db_host = False
db_port = False
db_user = odoo
db_password = odoo
addons_path = /opt/odoo/addons,/opt/odoo/extra-addons
logfile = /var/log/odoo/odoo.log
xmlrpc_interface = 127.0.0.1
EOF"
sudo chown odoo: /etc/odoo.conf
sudo chmod 640 /etc/odoo.conf

echo "Creando servicio de Odoo..."
sudo bash -c "cat > /etc/systemd/system/odoo.service <<EOF
[Unit]
Description=Odoo
Documentation=https://www.odoo.com
After=network.target postgresql.service

[Service]
User=odoo
ExecStart=/opt/odoo/odoo-venv/bin/python3 /opt/odoo/odoo-bin -c /etc/odoo.conf
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
EOF"

sudo systemctl daemon-reload
sudo systemctl enable odoo
sudo systemctl start odoo

# Configuración de Nginx
echo "Configurando Nginx para el dominio $dominio..."
sudo bash -c "cat > /etc/nginx/sites-available/$dominio <<'EOF'
server {
    listen 80;
    server_name www.$dominio $dominio;

    # Redirigir www a sin www
    if (\$host = www.$dominio) {
        return 301 http://$dominio\$request_uri;
    }

    # Redirigir tráfico HTTP a HTTPS
    location / {
        return 301 https://$dominio\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name $dominio;

    # Certificados SSL
    ssl_certificate /etc/letsencrypt/live/$dominio/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$dominio/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/$dominio/chain.pem;

    # Seguridad SSL
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    access_log /var/log/nginx/odoo-access.log;
    error_log /var/log/nginx/odoo-error.log;

    location / {
        proxy_pass http://127.0.0.1:8069;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 90;
        proxy_redirect off;
    }

    # Bloquear acceso directo a archivos XML-RPC
    location ~* /web/(static|tests) {
        allow all;
    }

    location ~* /xmlrpc/ {
        deny all;
    }
}
EOF"

# Crear enlace simbólico
if [ -L /etc/nginx/sites-enabled/$dominio ]; then
    sudo rm /etc/nginx/sites-enabled/$dominio
fi
sudo ln -s /etc/nginx/sites-available/$dominio /etc/nginx/sites-enabled/

echo "Verificando configuración de Nginx..."
sudo nginx -t

if [ $? -ne 0 ]; then
    echo "Error en la configuración de Nginx. Verifica el archivo de configuración."
    exit 1
fi

sudo systemctl reload nginx

# Generar certificados SSL con Let's Encrypt
echo "Generando certificados SSL con Let's Encrypt..."
sudo certbot --nginx -d $dominio -d www.$dominio --email $email --agree-tos --non-interactive --redirect

if [ $? -ne 0 ]; then
    echo "Error al generar el certificado SSL. Verifica la configuración del dominio."
    exit 1
fi

# Verificar renovación automática
echo "Verificando renovación automática del certificado..."
sudo certbot renew --dry-run

echo "-------------------------------------------------------------"
echo "¡Instalación completada con éxito!"
echo "Tu instancia de Odoo está disponible en https://$dominio"
