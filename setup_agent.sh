#!/bin/bash

# Récupère l'URL d'installation passée en argument
INSTALL_URL="$1"

# Vérifie si l'URL est valide
if [[ -z "$INSTALL_URL" ]]; then
    echo "Erreur : URL d'installation manquante. Exécution interrompue."
    exit 1
fi

echo "Récupération sécurisée des données de configuration..."

# Récupère les données depuis le serveur de provisionnement
CONFIG_DATA=$(curl -s "$INSTALL_URL")

# Vérifie si la récupération a réussi
if [[ "$CONFIG_DATA" != "{"* ]]; then
    echo "Erreur : Échec de la récupération des données ou token invalide."
    echo "Message du serveur : $CONFIG_DATA"
    exit 1
fi

# Parse les données JSON pour créer des variables
eval "$(echo "$CONFIG_DATA" | jq -r 'to_entries[] | "export \(.key)=\"\(.value)\""')"

# Récupérer les arguments passés par la commande curl
API_SECRET_FOR_AGENT=$AGENT_AUTH_TOKEN
VPS_IDENTIFIER="$2"

# --- Configuration du Log ---
LOG_FILE="/var/log/vps-agent-setup.log"
exec > >(tee -a "${LOG_FILE}") 2>&1
echo "--- Début du processus d'installation de l'agent VPS avec Docker et tunnel SSH ---"
echo "Date: $(date)"

# Vérification des pré-requis
if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit être exécuté avec les privilèges root. Utilisez 'sudo'."
    exit 1
fi
if [ -z "$API_SECRET_FOR_AGENT" ] || [ -z "$VPS_IDENTIFIER" ]; then
    echo "Erreur : Les arguments API_SECRET et VPS_IDENTIFIER sont manquants."
    echo "Utilisation: curl ... | sudo bash -s -- \"<API_SECRET>\" \"<VPS_IDENTIFIER>\""
    exit 1
fi

TUNNEL_RUN_USER=${SUDO_USER:-root}
HOME_DIR_TUNNEL_USER=$(eval echo "~${TUNNEL_RUN_USER}")

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "Distribution Linux non détectée. Ne peut pas continuer."
    exit 1
fi
echo "Système d'exploitation détecté: $OS"
echo "Le tunnel sera exécuté sous l'utilisateur: ${TUNNEL_RUN_USER}"
echo "Chemin de base des clés SSH pour le tunnel: ${HOME_DIR_TUNNEL_USER}/.ssh/"

# Installation de Docker et OpenSSH Client
echo "Installation des dépendances (Docker, OpenSSH Client, jq)..."
if [[ "$OS" == "debian" || "$OS" == "ubuntu" ]]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y && apt-get install -y ca-certificates curl gnupg openssh-client jq || { echo "Échec de l'installation des pré-requis APT."; exit 1; }

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg


    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -y && apt-get install -y docker-ce docker-ce-cli containerd.io || { echo "Échec de l'installation de Docker CE."; exit 1; }
elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "rocky" ]]; then
    yum install -y yum-utils device-mapper-persistent-data lvm2 openssh-clients jq || { echo "Échec de l'installation des pré-requis YUM."; exit 1; }
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    yum install -y docker-ce docker-ce-cli containerd.io || { echo "Échec de l'installation de Docker CE."; exit 1; }
    systemctl start docker
    systemctl enable docker
else
    echo "Installation de Docker non prise en charge pour cette distribution. Veuillez installer Docker manuellement."
    exit 1
fi
echo "Dépendances essentielles (Docker, jq) installées."

# Démarrage et configuration de l'agent Docker
echo "Démarrage et configuration de l'agent Docker..."
docker stop vps-agent-container > /dev/null 2>&1 || true
docker rm vps-agent-container > /dev/null 2>&1 || true
docker pull "$DOCKER_IMAGE_NAME" || { echo "Échec du pull de l'image Docker."; exit 1; }


#!/bin/bash

# --- Remplacement de la section Docker Run par Docker Swarm ---
echo "Démarrage et configuration de l'agent Docker en tant que service Swarm..."

# Initialisation du Swarm si ce n'est pas déjà fait
docker info | grep "Swarm: active" &> /dev/null || docker swarm init || { echo "Échec de l'initialisation de Swarm."; exit 1; }

# Nettoyage de l'ancien service si il existe
docker service rm observation-agent > /dev/null 2>&1 || true

# On ajoute un délai pour laisser le temps au service d'être complètement supprimé
echo "Délai de 5 secondes pour permettre la suppression du service..."
sleep 5

# --- Nouvelle étape : Vérification et libération automatique du port ---
echo "Vérification de la disponibilité du port $AGENT_PORT sur l'hôte et libération si nécessaire..."

# On récupère le PID du processus en écoute sur le port, en utilisant 'lsof -t'.
# L'option '-t' permet de n'afficher que le PID.
PID=$(sudo lsof -t -i:$AGENT_PORT)

if [ ! -z "$PID" ]; then
    echo "Le port $AGENT_PORT est déjà utilisé par le processus avec le PID $PID."
    echo "Arrêt automatique du processus..."
    
    # Utilisation de 'sudo kill -9' pour forcer l'arrêt du processus.
    # Le 'sudo' est nécessaire car le processus peut être lancé par un autre utilisateur (root).
    sudo kill -9 $PID
    
    echo "Processus $PID arrêté."
    # On ajoute un court délai pour s'assurer que le port est complètement libéré.
    sleep 2
else
    echo "Le port $AGENT_PORT est disponible."
fi

# Création du service Swarm
# NOTE : On utilise --mode=global pour garantir une seule tâche par nœud, évitant les conflits de ports
# NOTE : On supprime --publish car --network host expose déjà le port
docker service create \
  --name observation-agent \
  --network host \
  --mode global \
  --env API_SECRET="$API_SECRET_FOR_AGENT" \
  --env PORT="$AGENT_PORT" \
  "$DOCKER_IMAGE_NAME" || { echo "Échec de la création du service Docker Swarm."; exit 1; }

echo "Service Docker Swarm de l'agent lancé."


#docker run -d --restart=always --name vps-agent-container -e API_SECRET="$API_SECRET_FOR_AGENT" -e PORT="$AGENT_PORT" -p 127.0.0.1:"$AGENT_PORT":"$AGENT_PORT" "$DOCKER_IMAGE_NAME" || { echo "Échec du lancement du conteneur Docker."; exit 1; }
#echo "Conteneur Docker de l'agent lancé."

# Génération de la paire de clés SSH pour le tunnel
echo "Génération de la paire de clés SSH pour le tunnel..."
SSH_KEY_DIR="${HOME_DIR_TUNNEL_USER}/.ssh"
SSH_KEY_PATH="${SSH_KEY_DIR}/id_rsa_vps_tunnel"
mkdir -p "${SSH_KEY_DIR}" || { echo "Échec de la création du répertoire ${SSH_KEY_DIR}."; exit 1; }
chown "${TUNNEL_RUN_USER}":"${TUNNEL_RUN_USER}" "${SSH_KEY_DIR}" || { echo "Échec du chown sur ${SSH_KEY_DIR}."; exit 1; }
chmod 700 "${SSH_KEY_DIR}" || { echo "Échec du chmod sur ${SSH_KEY_DIR}."; exit 1; }
rm -f "${SSH_KEY_PATH}" "${SSH_KEY_PATH}.pub"
sudo -u "${TUNNEL_RUN_USER}" ssh-keygen -t rsa -b 4096 -f "${SSH_KEY_PATH}" -N "" || { echo "Échec de la génération de la clé SSH."; exit 1; }
chmod 600 "${SSH_KEY_PATH}"
chmod 600 "${SSH_KEY_PATH}.pub"
PUBLIC_KEY_FOR_TUNNEL=$(cat "${SSH_KEY_PATH}.pub")
echo "Clé publique du tunnel générée: ${PUBLIC_KEY_FOR_TUNNEL}"

# Envoi de la Clé Publique à votre Backend
echo "Envoi de la clé publique du tunnel à votre backend..."
BACKEND_API_URL="https://${YOUR_BACKEND_IP}:${BACKEND_PORT}/agent/register-tunnel-key"
AUTH_TOKEN_FOR_BACKEND=$(echo -n "$API_SECRET_FOR_AGENT" | sha256sum | awk '{print $1}')
curl_output=$(curl -s -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $AUTH_TOKEN_FOR_BACKEND" -d "{\"vpsId\": \"$VPS_IDENTIFIER\", \"publicKey\": \"$PUBLIC_KEY_FOR_TUNNEL\"}" "$BACKEND_API_URL")

if [ $? -ne 0 ]; then
    echo "Échec de la requête cURL vers le backend. Réponse: ${curl_output}"
    exit 1
else
    echo "Requête cURL envoyée. Réponse: ${curl_output}"
fi

# Extract the tunnelPort from the JSON response
TUNNEL_PORT_GET=$(echo "${curl_output}" | jq -r '.tunnelPort')

if [ $? -ne 0 ] || [ -z "$TUNNEL_PORT_GET" ] || [ "$TUNNEL_PORT_GET" = "null" ]; then
    echo "Erreur: Impossible d'obtenir un port de tunnel valide du backend." >&2
    exit 1
fi

# Démarrage du tunnel SSH inversé avec Systemd
echo "Lancement du tunnel SSH inversé avec Systemd..."
SERVICE_NAME="vps-tunnel.service"
SSH_COMMAND_ARGS="-N -T -R 0.0.0.0:${TUNNEL_PORT_GET}:localhost:${AGENT_PORT} -p ${SSH_PORT} -i ${SSH_KEY_PATH} -o ExitOnForwardFailure=yes -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -o BatchMode=yes ${SSH_TUNNEL_USER}@${YOUR_SSH_IP}"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"

echo "Tunnel port '${TUNNEL_PORT_GET}' registered and configured."

systemctl stop "${SERVICE_NAME}" > /dev/null 2>&1 || true
systemctl disable "${SERVICE_NAME}" > /dev/null 2>&1 || true

cat > "${SERVICE_FILE}" << EOF
[Unit]
Description=SSH Tunnel for VPS Agent
After=network.target

[Service]
ExecStartPre=/usr/bin/test -f ${SSH_KEY_PATH}
ExecStart=/usr/bin/ssh ${SSH_COMMAND_ARGS}
User=${TUNNEL_RUN_USER}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload || { echo "Échec de 'systemctl daemon-reload'."; exit 1; }
systemctl enable "${SERVICE_NAME}" || { echo "Échec de 'systemctl enable'."; exit 1; }
systemctl start "${SERVICE_NAME}" || { echo "Échec de 'systemctl start'."; exit 1; }

echo "Tunnel SSH inversé lancé et configuré pour démarrer au boot avec Systemd."

# Configuration du pare-feu (UFW)
echo "Configuration du pare-feu (UFW)..."
if command -v ufw &> /dev/null; then
    ufw allow "${SSH_PORT}/tcp" || { echo "Échec de l'ouverture du port SSH dans UFW."; exit 1; }
    ufw --force enable || { echo "Échec de l'activation de UFW."; exit 1; }
    echo "UFW configuré. Seul le port SSH (${SSH_PORT}) est ouvert pour l'extérieur."
else
    echo "UFW non installé. Ignore la configuration du pare-feu. Veuillez vous assurer que le port SSH est ouvert."
fi

if [[ "$OS" == "debian" || "$OS" == "ubuntu" ]]; then
    unset DEBIAN_FRONTEND
fi

# ================================================================
# Section ajoutée : Configuration du script de mise à jour automatique
# ================================================================

echo "--- Démarrage de la configuration de la mise à jour automatique ---"
UPDATE_SCRIPT_URL="https://raw.githubusercontent.com/codcodfr/observation-agent/main/update_agent.sh"
UPDATE_SCRIPT_PATH="/usr/local/bin/update_agent.sh"

# Télécharge le script de mise à jour depuis GitHub
echo "Téléchargement du script de mise à jour vers ${UPDATE_SCRIPT_PATH}..."
curl -sL "$UPDATE_SCRIPT_URL" | sudo tee "$UPDATE_SCRIPT_PATH" > /dev/null

# Rend le script exécutable
sudo chmod +x "$UPDATE_SCRIPT_PATH"
echo "Script de mise à jour rendu exécutable."

# Ajoute la tâche Cron pour l'exécution toutes les 5 minutes
echo "Ajout de la tâche Cron pour exécuter le script toutes les 5 minutes..."
CRON_JOB="*/5 * * * * ${UPDATE_SCRIPT_PATH}"
# Vérifie si la tâche existe déjà pour éviter les doublons
(sudo crontab -l 2>/dev/null | grep -F "$UPDATE_SCRIPT_PATH") || (echo "$CRON_JOB" | sudo crontab -)

echo "Tâche Cron ajoutée avec succès."
echo "--- Fin de la configuration de la mise à jour automatique ---"

# ================================================================

echo "--- Processus d'installation terminé ! ---"
echo "Vérifiez les logs du tunnel Systemd: journalctl -u ${SERVICE_NAME} -n 100"
echo "Statut du conteneur Docker: docker ps -a | grep vps-agent-container"