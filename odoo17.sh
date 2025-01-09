#!/bin/bash

# Comprobación de permisos
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, ejecuta este script como root."
  exit
fi

# Solicitar dominio para Odoo
read -p "Ingresa el dominio donde alojarás Odoo (ejemplo: odoo.midominio.com): " ODOO_DOMAIN

if [[ -z "$ODOO_DOMAIN" ]]; then
  echo "El dominio no puede estar vacío. Intenta de nuevo."
  exit 1
fi

# Actualizar el sistema
echo "Actualizando el sistema..."
sudo apt-get update && sudo apt-get upgrade -y

# Instalación de dependencias
echo "Instalando dependencias..."
sudo apt-get install -y git python3 python3-pip python3-dev build-essential wget \
python3-venv libpq-dev libjpeg-dev libxml2-dev libxslt1-dev zlib1g-dev libldap2-dev \
libsasl2-dev libffi-dev libssl-dev nodejs npm curl certbot nginx

# Instalación de PostgreSQL
echo "Instalando PostgreSQL..."
sudo apt-get install -y postgresql postgresql-client
sudo systemctl enable postgresql
sudo systemctl start postgresql

# Configuración de PostgreSQL
echo "Configurando PostgreSQL..."
sudo -u postgres createuser -s odoo || true
sudo -u postgres createdb odoo || true

# Crear usuario del sistema para Odoo
echo "Creando usuario del sistema para Odoo..."
sudo useradd -m -d /odoo -U -r -s /bin/bash odoo || true

# Descargar Odoo 17 Community
echo "Descargando Odoo 17..."
sudo -u odoo git clone https://github.com/odoo/odoo.git /odoo/odoo-server -b 17.0

# Crear entorno virtual de Python
echo "Creando entorno virtual..."
sudo -u odoo python3 -m venv /odoo/odoo-server/odoo-venv
source /odoo/odoo-server/odoo-venv/bin/activate
pip install -U pip setuptools wheel
pip install -r /odoo/odoo-server/requirements.txt || exit 1
deactivate

# Crear directorios necesarios
echo "Creando directorios para Odoo..."
sudo mkdir -p /odoo/odoo-server/{addons,filestore,config}
sudo chown -R odoo:odoo /odoo/

# Crear archivo de configuración
echo "Creando archivo de configuración..."
cat <<EOF | sudo tee /odoo/odoo-server/odoo.conf
[options]
admin_passwd = admin
db_host = False
db_port = False
db_user = odoo
db_password = False
addons_path = /odoo/odoo-server/addons
logfile = /odoo/odoo-server/odoo.log
proxy_mode = True
EOF
sudo chown odoo:odoo /odoo/odoo-server/odoo.conf
sudo chmod 640 /odoo/odoo-server/odoo.conf

# Configuración de Nginx
echo "Configurando Nginx..."
cat <<EOF | sudo tee /etc/nginx/sites-available/odoo
server {
    server_name $ODOO_DOMAIN;

    access_log /var/log/nginx/odoo-access.log;
    error_log /var/log/nginx/odoo-error.log;

    proxy_buffers 16 64k;
    proxy_buffer_size 128k;

    client_max_body_size 50M;

    location / {
        proxy_pass http://127.0.0.1:8069;
        proxy_redirect off;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

sudo ln -s /etc/nginx/sites-available/odoo /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl restart nginx

# Configuración SSL con Certbot
echo "Instalando y configurando SSL con Certbot..."
sudo certbot --nginx -d "$ODOO_DOMAIN" --non-interactive --agree-tos -m admin@"$ODOO_DOMAIN"

# Crear servicio para Odoo
echo "Creando servicio de Odoo..."
cat <<EOF | sudo tee /etc/systemd/system/odoo.service
[Unit]
Description=Odoo
Documentation=http://www.odoo.com
After=network.target

[Service]
Type=simple
User=odoo
ExecStart=/odoo/odoo-server/odoo-venv/bin/python3 /odoo/odoo-server/odoo-bin -c /odoo/odoo-server/odoo.conf
WorkingDirectory=/odoo/odoo-server
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable odoo
sudo systemctl start odoo

# Finalización
echo "Odoo 17 Community instalado y configurado en: http://$ODOO_DOMAIN"
