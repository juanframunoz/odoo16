#!/bin/bash
#
# Script de instalación de Odoo 16 Community en Ubuntu 22.04
# con localización española (OCA/l10n-spain) y tema de Cybrosys
# (similar al Enterprise).
#
# -------------------------------------------------------------------------
# Hace lo siguiente:
#  1) Actualiza y instala dependencias del sistema.
#  2) Crea un usuario de sistema para Odoo.
#  3) Instala PostgreSQL y configura un usuario para la BBDD.
#  4) Clona Odoo 16 y crea el entorno virtual Python.
#  5) Instala la localización española (l10n-spain).
#  6) Instala el tema 'backend_theme_cybrosys'.
#  7) Crea archivo de configuración y servicio systemd.
#  8) Inicia el servicio y deja todo listo.
# -------------------------------------------------------------------------

# == Variables de configuración ==
ODOO_USER="odoo16"
ODOO_HOME="/opt/odoo16"
ODOO_HOME_EXT="$ODOO_HOME/odoo-server"
ODOO_CONFIG="/etc/odoo16.conf"
ODOO_PORT="8069"
ODOO_VERSION="16.0"
ODOO_ADDONS="$ODOO_HOME/custom-addons"

echo "==========================================="
echo "   [1/8] Instalando dependencias básicas   "
echo "==========================================="
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install -y git python3-pip python3-dev build-essential \
    python3-venv python3-wheel libxslt-dev libzip-dev libldap2-dev \
    libsasl2-dev python3-setuptools node-less npm libjpeg-dev \
    libreoffice wkhtmltopdf postgresql

# (Opcional) Si quieres usar npm para compilar algunos assets, asegúrate de:
# sudo npm install -g less less-plugin-clean-css

echo "==========================================="
echo " [2/8] Creando usuario y carpetas de Odoo  "
echo "==========================================="
# Creamos usuario de sistema (sin shell)
sudo adduser --system --quiet --group --home "$ODOO_HOME" "$ODOO_USER"
# Directorio de logs
sudo mkdir -p /var/log/odoo16
sudo chown -R $ODOO_USER:$ODOO_USER /var/log/odoo16

echo "==========================================="
echo "  [3/8] Instalando y configurando Postgres "
echo "==========================================="
sudo systemctl enable postgresql
sudo systemctl start postgresql
# Crea un usuario postgres con el mismo nombre que ODOO_USER
sudo su - postgres -c "createuser -s $ODOO_USER" || true

echo "==========================================="
echo "   [4/8] Clonando Odoo 16 y venv Python    "
echo "==========================================="
# Clonamos Odoo en /opt/odoo16/odoo-server
sudo -u $ODOO_USER git clone --depth 1 --branch $ODOO_VERSION \
  https://github.com/odoo/odoo.git $ODOO_HOME_EXT

# Creamos entorno virtual
sudo -u $ODOO_USER python3 -m venv $ODOO_HOME/odoo-venv
# Activamos entorno virtual e instalamos dependencias
sudo -u $ODOO_USER bash -c "
  source $ODOO_HOME/odoo-venv/bin/activate
  pip install --upgrade pip
  pip install -r $ODOO_HOME_EXT/requirements.txt
  deactivate
"

echo "==========================================="
echo "  [5/8] Instalando localización española   "
echo "==========================================="
sudo -u $ODOO_USER mkdir -p $ODOO_ADDONS
cd $ODOO_ADDONS
sudo -u $ODOO_USER git clone https://github.com/OCA/l10n-spain.git

echo "==========================================="
echo " [6/8] Instalando tema 'backend_theme'     "
echo "==========================================="
cd $ODOO_ADDONS
# Clonamos el repo de Cybrosys (rama 16.0). Contiene, entre otros, backend_theme_cybrosys
sudo -u $ODOO_USER git clone --depth 1 --branch 16.0 \
  https://github.com/CybroOdoo/CybroAddons.git

# NOTA: El módulo "backend_theme_cybrosys" se encuentra dentro de CybroAddons
# en /CybroAddons/backend_theme_cybrosys

echo "==========================================="
echo " [7/8] Creando archivo de configuración    "
echo "==========================================="
sudo bash -c "cat > $ODOO_CONFIG" <<EOF
[options]
;--------------------------------------------------
; Configuración de Odoo 16
;--------------------------------------------------
admin_passwd = admin
db_host = False
db_port = False
db_user = $ODOO_USER
db_password = False
logfile = /var/log/odoo16/odoo.log
log_level = info
xmlrpc_port = $ODOO_PORT
; Rutas de addons (separadas por comas)
addons_path = $ODOO_HOME_EXT/addons,$ODOO_ADDONS/l10n-spain,$ODOO_ADDONS/CybroAddons/backend_theme_cybrosys

EOF

sudo chown $ODOO_USER:$ODOO_USER $ODOO_CONFIG
sudo chmod 640 $ODOO_CONFIG

echo "==========================================="
echo " [8/8] Creando servicio systemd y arrancando"
echo "==========================================="
sudo bash -c "cat > /etc/systemd/system/odoo16.service" <<EOF
[Unit]
Description=Odoo16
Requires=postgresql.service
After=network.target postgresql.service

[Service]
Type=simple
User=$ODOO_USER
Group=$ODOO_USER
SyslogIdentifier=odoo16
PermissionsStartOnly=true
ExecStart=$ODOO_HOME/odoo-venv/bin/python3 $ODOO_HOME_EXT/odoo-bin --config $ODOO_CONFIG
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
EOF

# Habilitamos e iniciamos el servicio
sudo systemctl daemon-reload
sudo systemctl enable odoo16
sudo systemctl start odoo16

echo "============================================================"
echo "  ¡Instalación completa de Odoo 16 con tema y loc. española!"
echo "============================================================"
echo " - Archivo de configuración: $ODOO_CONFIG"
echo " - Carpeta de logs: /var/log/odoo16"
echo " - Servicio: odoo16 (systemctl start|stop|status odoo16)"
echo " - Puerto por defecto: $ODOO_PORT"
echo "------------------------------------------------------------"
echo "  Accede a http://<IP_o_dominio>:$ODOO_PORT para usar Odoo."
echo "  Usuario master: en la base de datos, la contraseña admin"
echo "  (puedes cambiarla en $ODOO_CONFIG -> admin_passwd)."
echo "------------------------------------------------------------"
