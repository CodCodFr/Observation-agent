#!/bin/bash

# --- Configuration du Script de Setup ---
# URL de l'image Docker de votre agent sur GitHub Container Registry (GHCR)
# Assurez-vous que cette image est publique sur GHCR.
DOCKER_IMAGE_NAME="ghcr.io/codcodfr/observation-agent:latest"

AGENT_PORT="3000" # Port sur lequel l'agent écoutera DANS le conteneur Docker
YOUR_SSH_IP="152.53.104.19" # IP publique de votre serveur principal (À REMPLACER IMPÉRATIVEMENT)
YOUR_BACKEND_IP="codcod.fr" # IP publique de votre serveur principal (À REMPLACER IMPÉRATIVEMENT)
SSH_TUNNEL_USER="tunnel_user" # Utilisateur SSH créé sur votre backend pour le tunnel
BACKEND_PORT="7999" # Port de votre backend Node.js (celui qui reçoit la clé publique, ex: 3000)
TUNNEL_PORT="10000" # <--- NOUVEAU PORT : Le port que le tunnel va créer sur votre backend (doit être libre sur le backend)
SSH_PORT="22326" # Le port SSH de votre serveur backend (celui sur lequel sshd écoute pour les connexions entrantes)

# Récupérer les arguments passés par la commande curl
API_SECRET_FOR_AGENT="$1" # La clé secrète pour l'agent (générée par votre backend)
VPS_IDENTIFIER="$2" # L'ID unique de ce VPS (généré par votre backend)

# --- Configuration du Log ---
LOG_FILE="/var/log/vps-agent-setup.log"
# Redirige toute la sortie (stdout et stderr) vers le fichier de log et vers la console
exec > >(tee -a ${LOG_FILE}) 2>&1
echo "--- Début du processus d'installation de l'agent VPS avec Docker et tunnel SSH ---"
echo "Date: $(date)"

## 1. Pré-requis (détection OS, root check)
if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit être exécuté avec les privilèges root. Utilisez 'sudo su -' ou 'sudo bash'."
    exit 1
fi

# Determine the non-root user who invoked sudo, or default to root if sudo su - was used
# This user will own the SSH keys for the tunnel
TUNNEL_RUN_USER=${SUDO_USER:-root}
HOME_DIR_TUNNEL_USER=$(eval echo "~$TUNNEL_RUN_USER") # Get home directory of that user

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    echo "Distribution Linux non détectée. Ne peut pas continuer."
    exit 1
fi
echo "Système d'exploitation détecté: $OS $VER"
echo "Le tunnel sera exécuté sous l'utilisateur: $TUNNEL_RUN_USER"
echo "Chemin de base des clés SSH pour le tunnel: $HOME_DIR_TUNNEL_USER/.ssh/"

# --- GLOBAL SETTING FOR NON-INTERACTIVE APT (Débian/Ubuntu) ---
if [[ "$OS" == "debian" || "$OS" == "ubuntu" ]]; then
    export DEBIAN_FRONTEND=noninteractive
fi

## 2. Installation de Docker et OpenSSH Client
echo "Installation des dépendances (Docker, OpenSSH Client)..."

if [[ "$OS" == "debian" || "$OS" == "ubuntu" ]]; then
    echo "Tentative d'installation des pré-requis sans déclencher Dokku..."
    apt-get update -y || { echo "Échec de 'apt-get update'. Arrêt du script."; exit 1; }
    apt-get install -y ca-certificates curl gnupg openssh-client || { echo "Échec de l'installation des dépendances de base APT. Arrêt du script."; exit 1; }
    # Ajout de la clé GPG officielle de Docker:
    install -m 0755 -d /etc/apt/keyrings || { echo "Échec de création du répertoire keyrings. Arrêt du script."; exit 1; }
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg || { echo "Échec de l'ajout de la clé GPG Docker. Arrêt du script."; exit 1; }
    chmod a+r /etc/apt/keyrings/docker.gpg || { echo "Échec du chmod sur la clé GPG Docker. Arrêt du script."; exit 1; }
    # Ajout du dépôt Docker aux sources APT:
    echo \
      "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
      "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null || { echo "Échec de l'ajout du dépôt Docker. Arrêt du script."; exit 1; }
    apt-get update -y || { echo "Échec de 'apt-get update' après ajout dépôt Docker. Arrêt du script."; exit 1; }
    echo "Installation de Docker CE..."
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || { echo "Échec de l'installation de Docker. Arrêt du script."; exit 1; }
else
    echo "Installation de Docker non prise en charge pour cette distribution. Veuillez installer Docker manuellement."
    exit 1
fi

echo "Dépendances essentielles (Docker) installées."

## 3. Démarrage et configuration de l'agent Docker
echo "Démarrage et configuration de l'agent Docker..."
docker stop vps-agent-container > /dev/null 2>&1 || true
docker rm vps-agent-container > /dev/null 2>&1 || true
docker pull "$DOCKER_IMAGE_NAME" || { echo "Échec du pull de l'image Docker. Arrêt du script."; exit 1; }
docker run -d --restart=always \
  --name vps-agent-container \
  -e API_SECRET="$API_SECRET_FOR_AGENT" \
  -e PORT="$AGENT_PORT" \
  -p 127.0.0.1:"$AGENT_PORT":"$AGENT_PORT" \
  "$DOCKER_IMAGE_NAME" || { echo "Échec du lancement du conteneur Docker. Arrêt du script."; exit 1; }
echo "Conteneur Docker de l'agent lancé."

## 4. Génération de la paire de clés SSH pour le tunnel
echo "Génération de la paire de clés SSH pour le tunnel..."
SSH_KEY_DIR="$HOME_DIR_TUNNEL_USER/.ssh"
SSH_KEY_PATH="$SSH_KEY_DIR/id_rsa_vps_tunnel"
mkdir -p "$SSH_KEY_DIR" || { echo "Échec de la création du répertoire $SSH_KEY_DIR. Arrêt du script."; exit 1; }
chown "$TUNNEL_RUN_USER":"$TUNNEL_RUN_USER" "$SSH_KEY_DIR" || { echo "Échec du chown sur $SSH_KEY_DIR. Arrêt du script."; exit 1; }
chmod 700 "$SSH_KEY_DIR" || { echo "Échec du chmod sur $SSH_KEY_DIR. Arrêt du script."; exit 1; }
rm -f "$SSH_KEY_PATH" "$SSH_KEY_PATH.pub"
sudo -u "$TUNNEL_RUN_USER" ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" || { echo "Échec de la génération de la clé SSH. Arrêt du script."; exit 1; }
chmod 600 "$SSH_KEY_PATH" || { echo "Échec du chmod sur la clé privée SSH. Arrêt du script."; exit 1; }
chmod 600 "$SSH_KEY_PATH.pub" || { echo "Échec du chmod sur la clé publique SSH. Arrêt du script."; exit 1; }
PUBLIC_KEY_FOR_TUNNEL=$(cat "$SSH_KEY_PATH.pub")
echo "Clé publique du tunnel générée: $PUBLIC_KEY_FOR_TUNNEL"

## 5. Envoi de la Clé Publique à votre Backend
echo "Envoi de la clé publique du tunnel à votre backend..."
BACKEND_API_URL="https://${YOUR_BACKEND_IP}:${BACKEND_PORT}/agent/register-tunnel-key"
AUTH_TOKEN_FOR_BACKEND=$(echo -n "$API_SECRET_FOR_AGENT" | sha256sum | awk '{print $1}')
curl_output=$(curl -s -X POST \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer $AUTH_TOKEN_FOR_BACKEND" \
     -d "{\"vpsId\": \"$VPS_IDENTIFIER\", \"publicKey\": \"$PUBLIC_KEY_FOR_TUNNEL\"}" \
     "$BACKEND_API_URL")
if [ $? -ne 0 ]; then
    echo "Échec de la requête cURL vers le backend. Le tunnel ne fonctionnera peut-être pas."
    echo "Réponse cURL: $curl_output"
    exit 1
else
    echo "Requête cURL envoyée au backend. Réponse: $curl_output"
fi
echo "Clé publique envoyée au backend (vérifiez la réponse cURL ci-dessus)."

## 6. Démarrage du tunnel SSH inversé avec Systemd
echo "Lancement du tunnel SSH inversé avec Systemd..."
SERVICE_NAME="vps-tunnel.service"
SSH_COMMAND_ARGS="-N -T -R 0.0.0.0:$TUNNEL_PORT:localhost:$AGENT_PORT -p $SSH_PORT -i $SSH_KEY_PATH -o ExitOnForwardFailure=yes -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -o BatchMode=yes $SSH_TUNNEL_USER@$YOUR_SSH_IP"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"

# Création du fichier de service systemd
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=SSH Tunnel for VPS Agent
After=network.target

[Service]
ExecStart=/usr/bin/ssh $SSH_COMMAND_ARGS
User=$TUNNEL_RUN_USER
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Recharger systemd, activer et démarrer le service
systemctl daemon-reload || { echo "Échec de 'systemctl daemon-reload'. Arrêt du script."; exit 1; }
systemctl enable "$SERVICE_NAME" || { echo "Échec de 'systemctl enable'. Arrêt du script."; exit 1; }
systemctl start "$SERVICE_NAME" || { echo "Échec de 'systemctl start'. Arrêt du script."; exit 1; }

echo "Tunnel SSH inversé lancé et configuré pour démarrer au boot avec Systemd."

## 7. Configuration du pare-feu (UFW)
echo "Configuration du pare-feu (UFW) pour SSH..."
if [[ "$OS" == "debian" || "$OS" == "ubuntu" ]]; then
    apt-get install -y ufw || { echo "Échec de l'installation de UFW. Arrêt du script."; exit 1; }
    ufw allow $SSH_PORT/tcp || { echo "Échec de l'ouverture du port SSH dans UFW. Arrêt du script."; exit 1; }
    ufw --force enable || { echo "Échec de l'activation de UFW. Arrêt du script."; exit 1; }
    echo "UFW configuré. Seul le port SSH est ouvert pour l'extérieur."
else
    echo "Configuration de pare-feu non gérée pour cette distribution. Veuillez vous assurer que le port SSH ($SSH_PORT) est ouvert."
fi

# --- GLOBAL SETTING UNSET ---
if [[ "$OS" == "debian" || "$OS" == "ubuntu" ]]; then
    unset DEBIAN_FRONTEND
fi

echo "--- Processus d'installation terminé ! ---"
echo "Vérifiez les logs dans ${LOG_FILE}"
echo "Statut du conteneur Docker: docker ps -a | grep vps-agent-container"
echo "Statut du tunnel Systemd: systemctl status vps-tunnel.service"
echo "Logs du tunnel Systemd: journalctl -u vps-tunnel.service -n 100"
echo "Si tout est bon, votre backend peut maintenant communiquer avec ce VPS via le tunnel sur ${YOUR_BACKEND_IP}:${TUNNEL_PORT}"