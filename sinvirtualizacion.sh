#!/bin/bash
#
# Script de instalación de Odoo 16 Community en Ubuntu 20.04
# SIN uso de entorno virtual, instalando dependencias en el Python del sistema.
#
# ----------------------------------------------------------------------
# ATENCIÓN:
#  - Esto puede causar conflictos de paquetes Python a nivel de sistema.
#  - Normalmente se recomienda un venv o contenedor Docker.
# ----------------------------------------------------------------------
#  1) Actualiza e instala dependencias del sistema.
#  2) Crea usuario de sistema (odoo16) y carpeta /opt/odoo16.
#  3) Instala PostgreSQL y crea usuario BBDD.
#  4) Clona Odoo 16 en /opt/odoo16/odoo-server.
#  5) Instala requisitos de Odoo (system-wide) con pip --break-system-packages.
#  6) Clona localización española (l10n-spain).
#  7) Clona tema Cybrosys (backend_theme_cybrosys).
#  8) Crea archivo de configuración /etc/odoo16.conf.
#  9) Crea servicio systemd y arranca Odoo16.
# ----------------------------------------------------------------------

# == Variables de configuración ==
ODOO_USER="odoo16"
ODOO_HOME="/opt/odoo16"
ODOO_HOME_EXT="$ODOO_HOME/odoo-server"
ODOO_CONFIG="/etc/odoo16.conf"
ODOO_PORT="8069"
ODOO_VERSION="16.0"
ODOO_ADDONS="$ODOO_HOME/custom-addons"

echo "=========================================================="
echo "[1/9] Actualizando e instalando dependencias del sistema"
echo "=========================================================="
apt-get update
apt-get upgrade -y

# Dependencias para Odoo 16 (system-wide)
apt-get install -y git python3-pip python3-dev build-essential libpq-dev \
    libxml2-dev libxslt-dev libzip-dev libldap2-dev libsasl2-dev python3-setuptools \
    node-less npm libjpeg-dev libreoffice wkhtmltopdf postgresql

# Opcional: compilar assets con npm
# npm install -g less less-plugin-clean-css

echo "=========================================================="
echo "[2/9] Creando usuario de sistema (odoo16) y carpeta base"
echo "=========================================================="
if id "$ODOO_USER" &>/dev/null; then
  echo "El usuario $ODOO_USER ya existe. Continuando..."
else
  adduser --system --quiet --group --home "$ODOO_HOME" "$ODOO_USER"
fi

mkdir -p $ODOO_HOME
chown -R $ODOO_USER:$ODOO_USER $ODOO_HOME
chmod 755 $ODOO_HOME

# Carpeta para logs
mkdir -p /var/log/odoo16
chown -R $ODOO_USER:$ODOO_USER /var/log/odoo16

echo "=========================================================="
echo "[3/9] Instalando PostgreSQL y creando usuario de BBDD"
echo "=========================================================="
systemctl enable postgresql
systemctl start postgresql
# Crea un usuario postgres con el mismo nombre que ODOO_USER (superuser)
sudo -u postgres createuser -s $ODOO_USER 2>/dev/null || true

echo "=========================================================="
echo "[4/9] Clonando Odoo 16 en /opt/odoo16/odoo-server"
echo "=========================================================="
sudo -u $ODOO_USER git clone --depth 1 --branch $ODOO_VERSION \
  https://github.com/odoo/odoo.git $ODOO_HOME_EXT

echo "=========================================================="
echo "[5/9] Instalando requisitos de Odoo (system-wide)"
echo "=========================================================="
# ATENCIÓN: --break-system-packages fuerza a pip a instalar en el Python global,
# saltándose la protección 'externally-managed-environment' (PEP 668).
# Esto puede causar conflictos en el sistema.
pip install --upgrade pip --break-system-packages
pip install --break-system-packages -r $ODOO_HOME_EXT/requirements.txt

echo "=========================================================="
echo "[6/9] Clonando localización española (OCA/l10n-spain)"
echo "=========================================================="
sudo -u $ODOO_USER mkdir -p $ODOO_ADDONS
cd $ODOO_ADDONS
sudo -u $ODOO_USER git clone https://github.com/OCA/l10n-spain.git

echo "=========================================================="
echo "[7/9] Clonando tema Cybrosys (similar Enterprise)"
echo "=========================================================="
cd $ODOO_ADDONS
sudo -u $ODOO_USER git clone --depth 1 --branch 16.0 \
  https://github.com/CybroOdoo/CybroAddons.git

echo "=========================================================="
echo "[8/9] Creando archivo de configuración /etc/odoo16.conf"
echo "=========================================================="
cat > $ODOO_CONFIG <<EOF
[options]
;--------------------------------------------------
; Configuración de Odoo 16 (sin venv)
;--------------------------------------------------
admin_passwd = admin
db_host = False
db_port = False
db_user = $ODOO_USER
db_password = False
logfile = /var/log/odoo16/odoo.log
log_level = info
xmlrpc_port = $ODOO_PORT

; Rutas de addons
addons_path = $ODOO_HOME_EXT/addons,$ODOO_ADDONS/l10n-spain,$ODOO_ADDONS/CybroAddons/backend_theme_cybrosys
EOF

chown $ODOO_USER:$ODOO_USER $ODOO_CONFIG
chmod 640 $ODOO_CONFIG

echo "=========================================================="
echo "[9/9] Creando servicio systemd y arrancando Odoo16"
echo "=========================================================="
cat > /etc/systemd/system/odoo16.service <<EOF
[Unit]
Description=Odoo 16 (sin venv)
Requires=postgresql.service
After=network.target postgresql.service

[Service]
Type=simple
User=$ODOO_USER
Group=$ODOO_USER
SyslogIdentifier=odoo16
PermissionsStartOnly=true
ExecStart=/usr/bin/python3 $ODOO_HOME_EXT/odoo-bin --config $ODOO_CONFIG
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable odoo16
systemctl start odoo16

echo "============================================================"
echo "¡Instalación de Odoo 16 (sin venv) finalizada!"
echo "============================================================"
echo " - Archivo de configuración: $ODOO_CONFIG"
echo " - Servicio systemd: odoo16 (systemctl status|start|stop odoo16)"
echo " - Puerto por defecto: $ODOO_PORT"
echo "------------------------------------------------------------"
echo "  Accede a http://<IP>:$ODOO_PORT"
echo "  Contraseña master (admin_passwd): 'admin' (cámbiala)."
echo "------------------------------------------------------------"
echo "  ATENCIÓN: Has instalado dependencias en el Python del sistema."
echo "  Esto puede causar conflictos si instalas otros paquetes más adelante."
echo "============================================================"
