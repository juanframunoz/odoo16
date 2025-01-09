#!/bin/bash

# Script interactivo para configurar Odoo 17 con dominio personalizado y SSL de Let's Encrypt

# Solicitar el dominio del usuario
read -p "Introduce el dominio de tu servidor (ej. odoo17.tudominio.com): " DOMAIN
read -p "Introduce el correo electrónico para Let's Encrypt: " EMAIL

# Variables de configuración
ODOO_VERSION="17.0"
ODOO_DIR="/opt/odoo-server"
ODOO_USER="odoo"
ODOO_CONF="/etc/odoo/odoo.conf"
ODOO_DB_USER="odoo"
ODOO_DB_PASSWORD="odoo"
ODOO_PORT="8069"

# Actualizar el sistema
echo "Actualizando el sistema..."
sudo apt update && sudo apt upgrade -y

# Instalar dependencias necesarias para Odoo y Let's Encrypt
echo "Instalando dependencias..."
sudo apt install -y python3 python3-pip python3-dev python3-venv build-essential libxml2-dev libxslt1-dev zlib1g-dev libsasl2-dev libldap2-dev libssl-dev libmysqlclient-dev libjpeg-dev liblcms2-dev libblas-dev libatlas-base-dev libcurl4-openssl-dev libpq-dev git nginx certbot python3-certbot-nginx

# Crear el usuario de Odoo
echo "Creando usuario del sistema para Odoo..."
sudo useradd -m -U -r -d $ODOO_DIR -s /bin/bash $ODOO_USER

# Descargar Odoo desde GitHub
echo "Descargando Odoo desde GitHub..."
sudo git clone https://github.com/odoo/odoo.git --branch $ODOO_VERSION --single-branch $ODOO_DIR

# Crear entorno virtual para Odoo
echo "Creando entorno virtual de Python..."
sudo python3 -m venv $ODOO_DIR/odoo-venv

# Activar el entorno virtual
echo "Activando el entorno virtual..."
source $ODOO_DIR/odoo-venv/bin/activate

# Instalar dependencias de Python necesarias para Odoo
echo "Instalando dependencias de Python..."
pip install -r $ODOO_DIR/requirements.txt

# Salir del entorno virtual
deactivate

# Crear archivo de configuración de Odoo
echo "Creando archivo de configuración de Odoo..."
sudo mkdir -p /etc/odoo
cat <<EOL | sudo tee $ODOO_CONF
[options]
   ; This is the password that allows database operations:
   admin_passwd = admin
   db_host = False
   db_port = False
   db_user = $ODOO_DB_USER
   db_password = $ODOO_DB_PASSWORD
   db_filter = ^$ODOO_USER.*
   logfile = /var/log/odoo/odoo.log
   addons_path = $ODOO_DIR/addons
   data_dir = /var/lib/odoo
   longpolling_port = 8072
   xmlrpc_port = $ODOO_PORT
   proxy_mode = True
EOL

# Asegurarse de que los directorios de log y data sean accesibles por el usuario de Odoo
echo "Asegurando permisos del directorio..."
sudo mkdir -p /var/log/odoo
sudo chown -R $ODOO_USER:$ODOO_USER $ODOO_DIR /var/log/odoo /var/lib/odoo

# Crear un archivo de servicio para systemd
echo "Creando archivo de servicio de systemd para Odoo..."
cat <<EOL | sudo tee /etc/systemd/system/odoo.service
[Unit]
Description=Odoo
Documentation=http://www.odoo.com
After=network.target

[Service]
Type=simple
User=$ODOO_USER
ExecStart=$ODOO_DIR/odoo-venv/bin/python3 $ODOO_DIR/odoo-bin -c $ODOO_CONF
WorkingDirectory=$ODOO_DIR
Restart=always
LimitNOFILE=8192
LimitNPROC=8192

[Install]
WantedBy=default.target
EOL

# Recargar systemd y habilitar el servicio
echo "Recargando systemd y habilitando el servicio..."
sudo systemctl daemon-reload
sudo systemctl enable odoo
sudo systemctl start odoo

# Configurar Nginx como proxy inverso
echo "Configurando Nginx como proxy inverso..."
cat <<EOL | sudo tee /etc/nginx/sites-available/odoo
server {
    listen 80;
    server_name $DOMAIN;

    access_log /var/log/nginx/odoo.access.log;
    error_log /var/log/nginx/odoo.error.log;

    location / {
        proxy_pass http://127.0.0.1:$ODOO_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;
    }
}
EOL

# Habilitar el sitio de Nginx y reiniciar Nginx
echo "Habilitando el sitio de Nginx y reiniciando..."
sudo ln -s /etc/nginx/sites-available/odoo /etc/nginx/sites-enabled/
sudo systemctl restart nginx

# Configurar Let's Encrypt SSL
echo "Configurando SSL con Let's Encrypt..."
sudo certbot --nginx -d $DOMAIN --email $EMAIL --agree-tos --non-interactive

# Recargar Nginx para aplicar los cambios
echo "Recargando Nginx para aplicar los cambios de SSL..."
sudo systemctl reload nginx

# Finalización
echo "La instalación y configuración de Odoo 17 se ha completado con éxito."
echo "Accede a Odoo de manera segura en https://$DOMAIN"
