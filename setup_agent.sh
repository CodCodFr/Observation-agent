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
PM2_RUN_USER=${SUDO_USER:-root}
HOME_DIR_PM2_USER=$(eval echo "~$PM2_RUN_USER") # Get home directory of that user

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    echo "Distribution Linux non détectée. Ne peut pas continuer."
    exit 1
fi
echo "Système d'exploitation détecté: $OS $VER"
echo "Le tunnel sera exécuté sous l'utilisateur: $PM2_RUN_USER"
echo "Chemin de base des clés SSH pour le tunnel: $HOME_DIR_PM2_USER/.ssh/"

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

# PM2 est nécessaire pour gérer le tunnel SSH
echo "Installation de PM2..."
if ! command -v node &> /dev/null; then
    echo "Installation minimale de Node.js pour PM2..."
    if [[ "$OS" == "debian" || "$OS" == "ubuntu" ]]; then
        curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - || { echo "Échec du script d'installation NodeSource. Arrêt du script."; exit 1; }
        apt-get install -y nodejs || { echo "Échec de l'installation de Node.js. Arrêt du script."; exit 1; }
    elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "rocky" || "$OS" == "almalinux" ]]; then
        curl -fsSL https://rpm.nodesource.com/setup_lts.x | bash - || { echo "Échec du script d'installation NodeSource. Arrêt du script."; exit 1; }
        $PKG_MANAGER install -y nodejs || { echo "Échec de l'installation de Node.js. Arrêt du script."; exit 1; }
    fi
fi
npm install -g pm2 || { echo "Échec de l'installation de PM2. Arrêt du script."; exit 1; }
echo "Dépendances essentielles (Docker, PM2) installées."


## 3. Démarrage et configuration de l'agent Docker
echo "Démarrage et configuration de l'agent Docker..."

# Arrêter et supprimer l'ancien conteneur s'il existe
docker stop vps-agent-container > /dev/null 2>&1 || true
docker rm vps-agent-container > /dev/null 2>&1 || true

# Tirez la dernière image Docker depuis GHCR pour s'assurer que le code est à jour
docker pull "$DOCKER_IMAGE_NAME" || { echo "Échec du pull de l'image Docker. Arrêt du script."; exit 1; }

# Lancer le conteneur Docker de l'agent
# Les secrets API_SECRET et PORT sont passés comme variables d'environnement au conteneur
# Le port de l'agent est exposé sur l'interface localhost du VPS, pour être accessible par le tunnel SSH
docker run -d --restart=always \
  --name vps-agent-container \
  -e API_SECRET="$API_SECRET_FOR_AGENT" \
  -e PORT="$AGENT_PORT" \
  -p 127.0.0.1:"$AGENT_PORT":"$AGENT_PORT" \
  "$DOCKER_IMAGE_NAME" || { echo "Échec du lancement du conteneur Docker. Arrêt du script."; exit 1; }

echo "Conteneur Docker de l'agent lancé."

## 4. Génération de la paire de clés SSH pour le tunnel
echo "Génération de la paire de clés SSH pour le tunnel..."

# Define the absolute path for the SSH key for the PM2 user
SSH_KEY_DIR="$HOME_DIR_PM2_USER/.ssh"
SSH_KEY_PATH="$SSH_KEY_DIR/id_rsa_vps_tunnel"

# Ensure the .ssh directory exists and has correct permissions for the PM2_RUN_USER
mkdir -p "$SSH_KEY_DIR" || { echo "Échec de la création du répertoire $SSH_KEY_DIR. Arrêt du script."; exit 1; }
chown "$PM2_RUN_USER":"$PM2_RUN_USER" "$SSH_KEY_DIR" || { echo "Échec du chown sur $SSH_KEY_DIR. Arrêt du script."; exit 1; }
chmod 700 "$SSH_KEY_DIR" || { echo "Échec du chmod sur $SSH_KEY_DIR. Arrêt du script."; exit 1; }

# Supprime les clés existantes pour forcer la génération de nouvelles clés.
rm -f "$SSH_KEY_PATH" "$SSH_KEY_PATH.pub"

# Générer la clé SSH, en s'assurant qu'elle est créée avec l'utilisateur PM2_RUN_USER
# We're running as root, so we use 'sudo -u' to execute ssh-keygen as the target user.
sudo -u "$PM2_RUN_USER" ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" || { echo "Échec de la génération de la clé SSH. Arrêt du script."; exit 1; }

# Set permissions for the generated private key
chmod 600 "$SSH_KEY_PATH" || { echo "Échec du chmod sur la clé privée SSH. Arrêt du script."; exit 1; }
# Public key usually has 644, but 600 is also fine for security.
chmod 600 "$SSH_KEY_PATH.pub" || { echo "Échec du chmod sur la clé publique SSH. Arrêt du script."; exit 1; }

PUBLIC_KEY_FOR_TUNNEL=$(cat "$SSH_KEY_PATH.pub")
echo "Clé publique du tunnel générée: $PUBLIC_KEY_FOR_TUNNEL"

## 5. Envoi de la Clé Publique à votre Backend
echo "Envoi de la clé publique du tunnel à votre backend..."
# L'URL du backend est l'IP publique de votre VPS Backend
BACKEND_API_URL="https://${YOUR_BACKEND_IP}:${BACKEND_PORT}/agent/register-tunnel-key"
AUTH_TOKEN_FOR_BACKEND=$(echo -n "$API_SECRET_FOR_AGENT" | sha256sum | awk '{print $1}')

curl_output=$(curl -s -X POST \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer $AUTH_TOKEN_FOR_BACKEND" \
     -d "{\"vpsId\": \"$VPS_IDENTIFIER\", \"publicKey\": \"$PUBLIC_KEY_FOR_TUNNEL\"}" \
     "$BACKEND_API_URL")

# Check cURL exit code
if [ $? -ne 0 ]; then
    echo "Échec de la requête cURL vers le backend. Le tunnel ne fonctionnera peut-être pas."
    echo "Réponse cURL: $curl_output"
    exit 1
else
    echo "Requête cURL envoyée au backend. Réponse: $curl_output"
fi
echo "Clé publique envoyée au backend (vérifiez la réponse cURL ci-dessus)."

## 6. Démarrage du tunnel SSH inversé avec Systemd
echo "Lancement du tunnel SSH inversé avec Systemd (via PM2)..."

# Arrêter et supprimer l'ancien processus PM2 du tunnel s'il existe
sudo -u "$PM2_RUN_USER" /usr/bin/pm2 stop vps-tunnel > /dev/null 2>&1 || true
sudo -u "$PM2_RUN_USER" /usr/bin/pm2 delete v
