#!/bin/bash

# Comprobar si el script se ejecuta con privilegios de superusuario
if [[ $EUID -ne 0 ]]; then
   echo "Este script debe ser ejecutado como root o con sudo" 
   exit 1
fi

# Solicitar el dominio y el correo de Let's Encrypt al usuario
echo "Por favor, introduce el dominio de tu servidor (por ejemplo, ejemplo.com): "
read DOMAIN
echo "Por favor, introduce el correo electrónico para Let's Encrypt: "
read LETSENCRYPT_EMAIL

# Actualizar e instalar dependencias necesarias
echo "Actualizando el sistema y instalando dependencias..."
sudo apt update && sudo apt upgrade -y

# Instalar dependencias generales para Odoo y Let's Encrypt
sudo apt install -y python3-venv python3-dev python3-pip build-essential libssl-dev libffi-dev libxml2-dev libxslt1-dev zlib1g-dev libsasl2-dev libldap2-dev libjpeg8-dev liblcms2-dev libblas-dev libatlas-base-dev postgresql postgresql-contrib nginx certbot python3-certbot-nginx git

# Crear un nuevo usuario para Odoo
echo "Creando el usuario 'odoo' para ejecutar el servidor de Odoo..."
sudo adduser --system --home /opt/odoo --group --disabled-password --quiet odoo

# Crear el entorno virtual de Python para Odoo
echo "Creando un entorno virtual para Odoo..."
sudo -u odoo python3 -m venv /opt/odoo/odoo-venv

# Activar el entorno virtual e instalar las dependencias de Odoo
echo "Instalando las dependencias de Odoo..."
source /opt/odoo/odoo-venv/bin/activate
pip install --upgrade pip
pip install setuptools
pip install wheel
pip install -r /opt/odoo/requirements.txt

# Clonar el repositorio de Odoo 17
echo "Clonando Odoo 17 CE desde GitHub..."
sudo -u odoo git clone https://github.com/odoo/odoo.git /opt/odoo/odoo

# Configurar el archivo de configuración de Odoo
echo "Creando el archivo de configuración de Odoo..."
sudo cp /opt/odoo/odoo/debian/odoo.conf /opt/odoo/odoo.conf

# Configuración básica de Odoo
sudo sed -i "s|^db_host = .*|db_host = False|" /opt/odoo/odoo.conf
sudo sed -i "s|^db_user = .*|db_user = odoo|" /opt/odoo/odoo.conf
sudo sed -i "s|^db_password = .*|db_password = False|" /opt/odoo/odoo.conf
sudo sed -i "s|^admin_passwd = .*|admin_passwd = admin1234|" /opt/odoo/odoo.conf
sudo sed -i "s|^xmlrpc_port = .*|xmlrpc_port = 8069|" /opt/odoo/odoo.conf
sudo sed -i "s|^logfile = .*|logfile = /opt/odoo/odoo.log|" /opt/odoo/odoo.conf

# Establecer permisos adecuados
echo "Estableciendo los permisos correctos en los archivos de Odoo..."
sudo chown -R odoo: /opt/odoo

# Instalar y configurar Nginx
echo "Instalando y configurando Nginx..."
sudo apt install -y nginx

# Configuración de Nginx para Odoo
echo "Creando archivo de configuración para Nginx..."
cat <<EOL | sudo tee /etc/nginx/sites-available/odoo
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:8069;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOL

# Habilitar el sitio en Nginx
sudo ln -s /etc/nginx/sites-available/odoo /etc/nginx/sites-enabled/

# Configurar Certbot para Let's Encrypt
echo "Solicitando certificado SSL de Let's Encrypt..."
sudo certbot --nginx --non-interactive --agree-tos --email $LETSENCRYPT_EMAIL -d $DOMAIN

# Reiniciar Nginx para aplicar la configuración
echo "Reiniciando Nginx..."
sudo systemctl restart nginx

# Configurar Odoo para usar HTTPS
echo "Configurando Odoo para usar HTTPS..."
sudo sed -i "s|^xmlrpc_interface = .*|xmlrpc_interface = 127.0.0.1|" /opt/odoo/odoo.conf
sudo sed -i "s|^http_interface = .*|http_interface = 127.0.0.1|" /opt/odoo/odoo.conf
sudo sed -i "s|^http_port = .*|http_port = 8069|" /opt/odoo/odoo.conf

# Crear un servicio systemd para Odoo
echo "Creando un servicio systemd para Odoo..."
cat <<EOL | sudo tee /etc/systemd/system/odoo.service
[Unit]
Description=Odoo
Documentation=http://www.odoo.com
After=network.target

[Service]
Type=simple
User=odoo
ExecStart=/opt/odoo/odoo-venv/bin/python3 /opt/odoo/odoo/odoo-bin -c /opt/odoo/odoo.conf
WorkingDirectory=/opt/odoo
StandardOutput=journal+console
PIDFile=/opt/odoo/odoo.pid

[Install]
WantedBy=default.target
EOL

# Recargar systemd y habilitar el servicio
echo "Recargando systemd y habilitando el servicio Odoo..."
sudo systemctl daemon-reload
sudo systemctl enable odoo
sudo systemctl start odoo

# Finalizar
echo "¡La instalación de Odoo 17 CE con Let's Encrypt ha finalizado exitosamente!"
echo "Puedes acceder a Odoo a través de https://$DOMAIN"
