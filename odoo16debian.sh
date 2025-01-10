#!/bin/bash
#
# Script de instalación de Odoo 16 Community en Debian 12
# con localización española (OCA/l10n-spain) y tema Cybrosys.
#
# ----------------------------------------------------------------------
#  1) Actualiza e instala dependencias.
#  2) Crea usuario de sistema para Odoo.
#  3) Prepara carpeta /opt/odoo16 con permisos adecuados.
#  4) Instala y configura PostgreSQL, crea usuario BBDD.
#  5) Clona Odoo 16 y crea entorno virtual (venv).
#  6) Clona localización española.
#  7) Clona tema de Cybrosys.
#  8) Crea archivo de configuración y servicio systemd.
#  9) Inicia el servicio y deja todo listo.
# ----------------------------------------------------------------------

# == Variables principales ==
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
apt-get install -y git python3-pip python3-dev build-essential \
    python3-venv python3-wheel libxslt-dev libzip-dev libldap2-dev \
    libsasl2-dev python3-setuptools node-less npm libjpeg-dev \
    libreoffice wkhtmltopdf postgresql

# (Opcional) Para compilar assets vía npm:
# npm install -g less less-plugin-clean-css

echo "=========================================================="
echo "[2/9] Creando usuario de sistema (si no existe ya)"
echo "=========================================================="
# Creamos un usuario de sistema sin shell interactiva
if id "$ODOO_USER" &>/dev/null; then
  echo "El usuario $ODOO_USER ya existe. Continuando..."
else
  adduser --system --quiet --group --home "$ODOO_HOME" "$ODOO_USER"
fi

echo "=========================================================="
echo "[3/9] Preparando carpeta /opt/odoo16 con permisos"
echo "=========================================================="
mkdir -p $ODOO_HOME
chown -R $ODOO_USER:$ODOO_USER $ODOO_HOME
chmod 755 $ODOO_HOME

# Crear carpeta de logs
mkdir -p /var/log/odoo16
chown -R $ODOO_USER:$ODOO_USER /var/log/odoo16

echo "=========================================================="
echo "[4/9] Instalando PostgreSQL y creando usuario de BBDD"
echo "=========================================================="
systemctl enable postgresql
systemctl start postgresql
# Crea el usuario de PostgreSQL (superuser) con el mismo nombre que ODOO_USER
sudo -u postgres createuser -s $ODOO_USER 2>/dev/null || true

echo "=========================================================="
echo "[5/9] Clonando Odoo 16 y creando entorno virtual"
echo "=========================================================="
# Clonamos la rama 16.0 de Odoo a /opt/odoo16/odoo-server
sudo -u $ODOO_USER git clone --depth 1 --branch $ODOO_VERSION \
  https://github.com/odoo/odoo.git $ODOO_HOME_EXT

# Crear y activar venv
sudo -u $ODOO_USER python3 -m venv $ODOO_HOME/odoo-venv

sudo -u $ODOO_USER bash -c "
  source $ODOO_HOME/odoo-venv/bin/activate
  pip install --upgrade pip
  pip install -r $ODOO_HOME_EXT/requirements.txt
  deactivate
"

echo "=========================================================="
echo "[6/9] Clonando localización española (OCA/l10n-spain)"
echo "=========================================================="
sudo -u $ODOO_USER mkdir -p $ODOO_ADDONS
cd $ODOO_ADDONS
sudo -u $ODOO_USER git clone https://github.com/OCA/l10n-spain.git

echo "=========================================================="
echo "[7/9] Clonando tema Cybrosys (similar a Enterprise)"
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
; Configuración de Odoo 16 en Debian 12
;--------------------------------------------------
admin_passwd = admin
db_host = False
db_port = False
db_user = $ODOO_USER
db_password = False
logfile = /var/log/odoo16/odoo.log
log_level = info
xmlrpc_port = $ODOO_PORT
; Ruta de addons (varias rutas separadas por comas)
addons_path = $ODOO_HOME_EXT/addons,$ODOO_ADDONS/l10n-spain,$ODOO_ADDONS/CybroAddons/backend_theme_cybrosys
EOF

chown $ODOO_USER:$ODOO_USER $ODOO_CONFIG
chmod 640 $ODOO_CONFIG

echo "=========================================================="
echo "[9/9] Creando servicio systemd y arrancando Odoo 16"
echo "=========================================================="
cat > /etc/systemd/system/odoo16.service <<EOF
[Unit]
Description=Odoo 16
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

systemctl daemon-reload
systemctl enable odoo16
systemctl start odoo16

echo "============================================================"
echo "  ¡Instalación de Odoo 16 con localización española y tema!"
echo "============================================================"
echo " - Archivo de configuración: $ODOO_CONFIG"
echo " - Carpeta de logs: /var/log/odoo16"
echo " - Servicio: odoo16 (systemctl status|start|stop odoo16)"
echo " - Puerto por defecto: $ODOO_PORT"
echo "------------------------------------------------------------"
echo "  Accede a http://<IP>:$ODOO_PORT para usar Odoo."
echo "  Contraseña master (admin_passwd): 'admin' (cámbiala)."
echo "------------------------------------------------------------"
