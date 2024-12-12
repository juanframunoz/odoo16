#!/bin/bash

# Solicitar dominio al usuario
echo "Por favor, ingresa tu dominio (sin 'www.'):"
read DOMAIN

# Verificar que el dominio no esté vacío
if [ -z "$DOMAIN" ]; then
    echo "[ERROR] El dominio no puede estar vacío. Por favor, intenta de nuevo."
    exit 1
fi

ODOO_USER="odoo"
ODOO_HOME="/opt/odoo"
ODOO_CONFIG="/etc/odoo.conf"
NGINX_SITE="/etc/nginx/sites-available/odoo"

# Actualizar el sistema
echo "[INFO] Actualizando el sistema..."
sudo apt update && sudo apt upgrade -y

# Instalar dependencias básicas
echo "[INFO] Instalando dependencias básicas..."
sudo apt install -y wget curl git python3-pip build-essential libssl-dev libffi-dev python3-dev python3-venv libpq-dev postgresql nginx certbot python3-certbot-nginx

# Crear usuario para Odoo
echo "[INFO] Creando usuario Odoo..."
sudo adduser --system --home=$ODOO_HOME --group $ODOO_USER

# Instalar PostgreSQL
echo "[INFO] Configurando PostgreSQL..."
sudo su - postgres -c "createuser -s $ODOO_USER"

# Descargar Odoo 17
echo "[INFO] Descargando Odoo 17..."
sudo git clone https://github.com/odoo/odoo.git --branch 17.0 --single-branch $ODOO_HOME/odoo

# Instalar dependencias de Python
echo "[INFO] Instalando dependencias de Python..."
sudo pip3 install -r $ODOO_HOME/odoo/requirements.txt

# Crear archivo de configuración para Odoo
echo "[INFO] Creando archivo de configuración..."
sudo bash -c "cat > $ODOO_CONFIG" <<EOF
[options]
addons_path = $ODOO_HOME/odoo/addons
data_dir = /var/lib/odoo
db_host = False
db_port = False
db_user = $ODOO_USER
db_password = False
logfile = /var/log/odoo/odoo.log
EOF

# Crear directorios necesarios
echo "[INFO] Creando directorios necesarios..."
sudo mkdir -p /var/lib/odoo /var/log/odoo
sudo chown $ODOO_USER:$ODOO_USER /var/lib/odoo /var/log/odoo

# Crear servicio de Odoo
echo "[INFO] Creando servicio systemd para Odoo..."
sudo bash -c "cat > /etc/systemd/system/odoo.service" <<EOF
[Unit]
Description=Odoo
Documentation=https://www.odoo.com/documentation/17.0/
After=network.target postgresql.service

[Service]
User=$ODOO_USER
Group=$ODOO_USER
ExecStart=/usr/bin/python3 $ODOO_HOME/odoo/odoo-bin -c $ODOO_CONFIG
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
EOF

# Iniciar y habilitar el servicio de Odoo
echo "[INFO] Iniciando y habilitando Odoo..."
sudo systemctl daemon-reload
sudo systemctl enable odoo
sudo systemctl start odoo

# Configurar Nginx para Odoo
echo "[INFO] Configurando Nginx..."
sudo bash -c "cat > $NGINX_SITE" <<EOF
server {
    server_name $DOMAIN www.$DOMAIN;

    access_log /var/log/nginx/odoo.access.log;
    error_log /var/log/nginx/odoo.error.log;

    location / {
        proxy_pass http://127.0.0.1:8069;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    client_max_body_size 100M;

    # Redirigir www a no-www
    if ($host = www.$DOMAIN) {
        return 301 https://$DOMAIN$request_uri;
    }
}
EOF

sudo ln -s $NGINX_SITE /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# Configurar SSL con Let's Encrypt
echo "[INFO] Configurando SSL con Let's Encrypt..."
sudo certbot --nginx -d $DOMAIN -d www.$DOMAIN

# Verificar renovación automática de SSL
echo "[INFO] Probando renovación automática de SSL..."
sudo certbot renew --dry-run

# Finalización
echo "[INFO] Instalación y configuración completadas. Accede a https://$DOMAIN para usar Odoo."
