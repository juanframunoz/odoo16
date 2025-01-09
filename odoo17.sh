#!/bin/bash

# Pide el dominio para la configuración
echo "Por favor, introduce el dominio donde se alojará Odoo (ejemplo: midominio.com): "
read DOMAIN

# Actualizar el sistema
echo "Actualizando el sistema..."
sudo apt update -y
sudo apt upgrade -y

# Instalar dependencias básicas
echo "Instalando dependencias básicas..."
sudo apt install -y wget curl gnupg2 ca-certificates lsb-release sudo software-properties-common build-essential

# Añadir repositorio de Python 3.8
echo "Añadiendo repositorio de Python 3.8..."
sudo add-apt-repository ppa:deadsnakes/ppa -y
sudo apt update -y

# Instalar Python 3.8 y dependencias necesarias
echo "Instalando Python 3.8..."
sudo apt install -y python3.8 python3.8-venv python3.8-dev python3-pip libxml2-dev libxslt1-dev zlib1g-dev libsasl2-dev libldap2-dev build-essential libssl-dev libmysqlclient-dev

# Instalar y configurar pip
echo "Instalando pip para Python 3.8..."
python3.8 -m ensurepip --upgrade
python3.8 -m pip install --upgrade pip setuptools wheel

# Crear un usuario para Odoo si no existe
echo "Creando usuario de Odoo..."
sudo useradd --system --home /opt/odoo --create-home --shell /bin/bash --group odoo

# Descargar y descomprimir Odoo
echo "Descargando Odoo..."
cd /opt
sudo wget https://github.com/odoo/odoo/archive/refs/tags/17.0.tar.gz
sudo tar -xzvf 17.0.tar.gz
sudo mv odoo-17.0 odoo-server
cd odoo-server

# Crear entorno virtual de Python
echo "Creando entorno virtual en /opt/odoo-server..."
python3.8 -m venv odoo-venv
source odoo-venv/bin/activate

# Instalar las dependencias de Odoo
echo "Instalando dependencias de Odoo..."
pip install -r /opt/odoo-server/requirements.txt

# Configurar Odoo
echo "Configurando Odoo..."
sudo cp /opt/odoo-server/debian/odoo.conf /etc/odoo.conf
sudo chmod 755 /etc/odoo.conf

# Editar la configuración de Odoo
sudo sed -i "s/;admin_passwd = admin/admin_passwd = admin/g" /etc/odoo.conf
sudo sed -i "s/;db_host = False/db_host = False/g" /etc/odoo.conf
sudo sed -i "s/;db_port = False/db_port = False/g" /etc/odoo.conf
sudo sed -i "s/;db_user = False/db_user = odoo/g" /etc/odoo.conf
sudo sed -i "s/;db_password = False/db_password = False/g" /etc/odoo.conf
sudo sed -i "s/;proxy_mode = False/proxy_mode = True/g" /etc/odoo.conf
sudo sed -i "s/;addons_path = addons/addons_path = \/opt\/odoo-server\/addons/g" /etc/odoo.conf
sudo sed -i "s/;logfile = False/logfile = \/var\/log\/odoo\/odoo.log/g" /etc/odoo.conf

# Crear el directorio de logs
sudo mkdir /var/log/odoo
sudo chown odoo:odoo /var/log/odoo

# Configurar servicio de Odoo
echo "Configurando el servicio de Odoo..."
cat <<EOL | sudo tee /etc/systemd/system/odoo.service
[Unit]
Description=Odoo
Documentation=http://www.odoo.com
After=network.target

[Service]
Type=simple
User=odoo
ExecStart=/opt/odoo-server/odoo-venv/bin/python3 /opt/odoo-server/odoo-bin -c /etc/odoo.conf
WorkingDirectory=/opt/odoo-server
StandardOutput=journal
StandardError=journal
Restart=always

[Install]
WantedBy=default.target
EOL

# Recargar systemd y habilitar Odoo
echo "Recargando systemd y habilitando Odoo..."
sudo systemctl daemon-reload
sudo systemctl enable odoo
sudo systemctl start odoo

# Instalar certificado SSL (opcional)
echo "Instalando Let's Encrypt SSL (solo si tienes un dominio)..."
if [ ! -z "$DOMAIN" ]; then
    sudo apt install -y certbot python3-certbot-nginx
    sudo certbot --nginx -d $DOMAIN
    sudo systemctl reload nginx
else
    echo "No se ha configurado un dominio. Saltando instalación de SSL."
fi

# Mostrar URL para acceder a Odoo
echo "Odoo está instalado y en ejecución. Accede a tu instancia en:"
echo "http://$DOMAIN:8069"
