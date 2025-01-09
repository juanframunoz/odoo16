#!/bin/bash

# Formulario interactivo para ingresar el dominio
read -p "Por favor, ingresa tu dominio (ejemplo: midominio.com): " DOMAIN

if [[ -z "$DOMAIN" ]]; then
  echo "No ingresaste un dominio. Por favor, vuelve a ejecutar el script e ingresa uno válido."
  exit 1
fi

# Actualizar el sistema
echo "Actualizando el sistema..."
sudo apt update && sudo apt upgrade -y

# Instalación de dependencias
echo "Instalando dependencias..."
sudo apt install -y git python3 python3-pip python3-dev build-essential wget \
python3-venv libpq-dev libjpeg-dev libxml2-dev libxslt1-dev zlib1g-dev libldap2-dev \
libsasl2-dev libffi-dev libssl-dev nodejs npm curl

# Configurar Node.js y npm
echo "Instalando Node.js y npm..."
sudo npm install -g less less-plugin-clean-css rtlcss

# Instalar y configurar PostgreSQL
echo "Instalando PostgreSQL..."
sudo apt install -y postgresql postgresql-contrib
sudo systemctl enable postgresql
sudo systemctl start postgresql

echo "Creando usuario y base de datos de Odoo..."
sudo -u postgres createuser -s odoo
sudo -u postgres psql -c "ALTER USER odoo WITH PASSWORD 'odoo';"

# Clonar el repositorio de Odoo 17
echo "Clonando el repositorio de Odoo 17 Community..."
sudo mkdir -p /odoo/odoo-server
sudo chown -R $USER:$USER /odoo
cd /odoo
git clone --depth 1 --branch 17.0 https://github.com/odoo/odoo.git odoo-server

# Crear entorno virtual y activar
echo "Creando entorno virtual para Odoo..."
cd /odoo/odoo-server
python3 -m venv odoo-venv
source odoo-venv/bin/activate

# Instalar dependencias de Python
echo "Instalando dependencias de Python..."
pip3 install wheel
pip3 install -r requirements.txt

# Crear usuario del sistema para Odoo
echo "Creando usuario del sistema para Odoo..."
sudo useradd -m -d /home/odoo -U -r -s /bin/bash odoo
sudo mkdir -p /var/lib/odoo /var/log/odoo
sudo chown -R odoo:odoo /var/lib/odoo /var/log/odoo /odoo

# Configurar archivo de configuración de Odoo
echo "Configurando Odoo..."
sudo tee /etc/odoo.conf > /dev/null <<EOL
[options]
addons_path = /odoo/odoo-server/addons
data_dir = /var/lib/odoo
logfile = /var/log/odoo/odoo.log
admin_passwd = admin
db_host = False
db_port = False
db_user = odoo
db_password = odoo
proxy_mode = True
EOL

sudo chown odoo:odoo /etc/odoo.conf
sudo chmod 640 /etc/odoo.conf

# Configurar servicio systemd
echo "Configurando el servicio de Odoo..."
sudo tee /etc/systemd/system/odoo.service > /dev/null <<EOL
[Unit]
Description=Odoo
Documentation=http://www.odoo.com
Requires=postgresql.service
After=network.target postgresql.service

[Service]
Type=simple
SyslogIdentifier=odoo
PermissionsStartOnly=true
User=odoo
Group=odoo
ExecStart=/odoo/odoo-server/odoo-bin -c /etc/odoo.conf
WorkingDirectory=/odoo/
