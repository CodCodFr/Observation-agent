#!/bin/bash

# --- Configuration du Script de Setup ---
# URL de votre dépôt GitHub (utilisez l'URL HTTPS pour le clonage)
AGENT_REPO_URL="https://github.com/CodCodFr/Observation-agent.git"
AGENT_DIR_IN_REPO="" # Le sous-répertoire où se trouvent les fichiers de l'agent dans votre dépôt (ici, 'agent/')

AGENT_PORT="3001" # Port sur lequel l'agent écoutera localement
YOUR_BACKEND_IP="VOTRE_IP_PUBLIQUE_DU_BACKEND" # IP publique de votre serveur principal (à remplacer)
SSH_TUNNEL_USER="tunnel_user" # Utilisateur SSH créé sur votre backend
TUNNEL_PORT="10000" # Le port que le tunnel va créer sur votre backend (à remplacer si vous en utilisez un autre)

# Récupérer les arguments passés par la commande curl
API_SECRET_FOR_AGENT="$1" # La clé secrète pour l'agent (générée par votre backend)
VPS_IDENTIFIER="$2"       # L'ID unique de ce VPS (généré par votre backend)

LOG_FILE="/var/log/vps-agent-setup.log"
exec > >(tee -a ${LOG_FILE}) 2>&1
echo "--- Début du processus d'installation de l'agent VPS avec tunnel SSH ---"
echo "Date: $(date)"

# --- Pré-requis (détection OS, root check) ---
if [ "$EUID" -ne 0 ]; then echo "Ce script doit être exécuté avec les privilèges root."; exit 1; fi
if [ -f /etc/os-release ]; then . /etc/os-release; OS=$ID; VER=$VERSION_ID; else echo "Distribution Linux non détectée."; exit 1; fi
echo "Système d'exploitation détecté: $OS $VER"

# --- 1. Installation de Node.js, NPM, PM2, OpenSSH Client, et Git ---
echo "1. Installation des dépendances (Node.js, NPM, PM2, OpenSSH Client, Git)..."
if [[ "$OS" == "debian" || "$OS" == "ubuntu" ]]; then
    apt-get update
    apt-get install -y curl openssh-client git # Ajout de git ici
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
    apt-get install -y nodejs npm
elif [[ "$OS" == "centos" || "$OS" == "rhel" ]]; then
    yum install -y curl openssh-clients git # Ajout de git ici
    curl -fsSL https://rpm.nodesource.com/setup_lts.x | bash -
    yum install -y nodejs npm
else
    echo "Installation de Node.js non prise en charge pour cette distribution."
    exit 1
fi
npm install -g pm2
echo "Dépendances installées."

# --- 2. Création du répertoire de l'agent et clonage du dépôt GitHub ---
echo "2. Création du répertoire de l'agent et clonage du dépôt GitHub..."
AGENT_INSTALL_DIR="/opt/vps-agent"
mkdir -p "$AGENT_INSTALL_DIR"
cd "$AGENT_INSTALL_DIR" || { echo "Échec de cd vers $AGENT_INSTALL_DIR"; exit 1; }

# Cloner le dépôt et copier les fichiers de l'agent au bon endroit
git clone "$AGENT_REPO_URL" temp_repo || { echo "Échec du clonage du dépôt Git"; exit 1; }
cp -r temp_repo/"$AGENT_DIR_IN_REPO"/* . || { echo "Échec de la copie des fichiers de l'agent"; exit 1; }
rm -rf temp_repo # Nettoyer le dépôt cloné temporaire

echo "Fichiers de l'agent téléchargés depuis GitHub."

# --- 3. Installation des dépendances NPM de l'agent ---
echo "3. Installation des dépendances NPM de l'agent..."
npm install --production || { echo "Échec de l'installation des dépendances NPM"; exit 1; }
echo "Dépendances NPM installées."

# --- 4. Configuration de l'agent (fichier .env) ---
echo "4. Configuration de l'agent..."
echo "API_SECRET=$API_SECRET_FOR_AGENT" > .env
echo "PORT=$AGENT_PORT" >> .env
echo "Fichier .env créé pour l'agent."

# --- 5. Démarrage de l'Agent Node.js (écoute sur localhost) ---
echo "5. Lancement de l'Agent Node.js avec PM2..."
pm2 start agent.js --name vps-agent -- restart-delay 5000
pm2 save
echo "Agent VPS lancé avec PM2."

# --- 6. Génération de la paire de clés SSH pour le tunnel ---
echo "6. Génération de la paire de clés SSH pour le tunnel..."
SSH_KEY_PATH="$HOME/.ssh/id_rsa_vps_tunnel" # Clé stockée dans le home de l'utilisateur root
ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" # Pas de passphrase
chmod 600 "$SSH_KEY_PATH"
chmod 600 "$SSH_KEY_PATH.pub"

PUBLIC_KEY_FOR_TUNNEL=$(cat "$SSH_KEY_PATH.pub")
echo "Clé publique du tunnel générée: $PUBLIC_KEY_FOR_TUNNEL"

# --- 7. Envoi de la Clé Publique à votre Backend ---
echo "7. Envoi de la clé publique du tunnel à votre backend..."
BACKEND_API_URL="http://${YOUR_BACKEND_IP}:${BACKEND_PORT}/api/register-tunnel-key" # Utilisez l'IP et le port de votre backend
AUTH_TOKEN_FOR_BACKEND=$(echo -n "$API_SECRET_FOR_AGENT" | sha256sum | awk '{print $1}') # L'API_SECRET de l'agent sert d'authentification ici

curl -X POST \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer $AUTH_TOKEN_FOR_BACKEND" \
     -d "{\"vpsId\": \"$VPS_IDENTIFIER\", \"publicKey\": \"$PUBLIC_KEY_FOR_TUNNEL\"}" \
     "$BACKEND_API_URL" || { echo "Échec de l'envoi de la clé publique au backend. Le tunnel ne fonctionnera pas."; exit 1; }
echo "Clé publique envoyée au backend."

# --- 8. Démarrage du tunnel SSH inversé avec PM2 ---
echo "8. Lancement du tunnel SSH inversé avec PM2..."
PM2_TUNNEL_ARGS="-N -T -R 0.0.0.0:$TUNNEL_PORT:localhost:$AGENT_PORT -i $SSH_KEY_PATH -o ExitOnForwardFailure=yes -o ServerAliveInterval=60 -o ServerAliveCountMax=3 $SSH_TUNNEL_USER@$YOUR_BACKEND_IP"
pm2 start ssh --name vps-tunnel -- "$PM2_TUNNEL_ARGS" || { echo "Échec du démarrage du tunnel SSH."; exit 1; }
pm2 save
pm2 startup systemd # Assure que PM2 et ses processus (agent, tunnel) démarrent au boot

echo "Tunnel SSH inversé lancé avec PM2 et configuré pour démarrer au boot."

# --- 9. Configuration du pare-feu (UFW) ---
echo "9. Configuration du pare-feu (UFW) pour SSH..."
if [[ "$OS" == "debian" || "$OS" == "ubuntu" ]]; then
    apt-get install -y ufw
    ufw allow ssh # S'assurer que le SSH reste accessible pour l'utilisateur
    ufw --force enable
    echo "UFW configuré. Seul le port SSH est ouvert pour l'extérieur."
else
    echo "Configuration de pare-feu non gérée pour cette distribution. Veuillez vous assurer que le port SSH (22) est ouvert."
fi

echo "--- Processus d'installation terminé ! ---"
echo "Vérifiez les logs dans ${LOG_FILE}"
echo "Statut de l'agent PM2: pm2 status vps-agent"
echo "Statut du tunnel PM2: pm2 status vps-tunnel"
echo "Si tout est bon, votre backend peut maintenant communiquer avec ce VPS via le tunnel sur ${YOUR_BACKEND_IP}:${TUNNEL_PORT}"