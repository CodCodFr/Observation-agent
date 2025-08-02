#!/bin/bash

# --- Configuration du Script de Setup ---
# URL de votre dépôt GitHub (utilisez l'URL HTTPS pour le clonage)
AGENT_REPO_URL="https://github.com/CodCodFr/Observation-agent.git"
AGENT_DIR_IN_REPO="" # Le sous-répertoire où se trouvent les fichiers de l'agent dans votre dépôt (ici, 'agent/')

AGENT_PORT="3001" # Port sur lequel l'agent écoutera localement
YOUR_BACKEND_IP="VOTRE_IP_PUBLIQUE_DU_BACKEND" # IP publique de votre serveur principal (À REMPLACER IMPÉRATIVEMENT)
SSH_TUNNEL_USER="tunnel_user" # Utilisateur SSH créé sur votre backend
BACKEND_PORT="3000" # Port de votre backend Node.js (celui qui reçoit la clé publique, ex: 3000)
TUNNEL_PORT="10000" # Le port que le tunnel va créer sur votre backend (À REMPLACER si vous en utilisez un autre ou un système dynamique)

# Récupérer les arguments passés par la commande curl
API_SECRET_FOR_AGENT="$1" # La clé secrète pour l'agent (générée par votre backend)
VPS_IDENTIFIER="$2"       # L'ID unique de ce VPS (généré par votre backend)

LOG_FILE="/var/log/vps-agent-setup.log"
exec > >(tee -a ${LOG_FILE}) 2>&1
echo "--- Début du processus d'installation de l'agent VPS avec tunnel SSH ---"
echo "Date: $(date)"

# --- Pré-requis (détection OS, root check) ---
if [ "$EUID" -ne 0 ]; then
  echo "Ce script doit être exécuté avec les privilèges root. Utilisez 'sudo su -' ou 'sudo bash'."
  exit 1
fi

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    echo "Distribution Linux non détectée. Ne peut pas continuer."
    exit 1
fi
echo "Système d'exploitation détecté: $OS $VER"

# --- 1. Installation de Node.js, NPM, PM2, OpenSSH Client, et Git ---
echo "1. Installation des dépendances (Node.js, NPM, PM2, OpenSSH Client, Git)..."
if [[ "$OS" == "debian" || "$OS" == "ubuntu" ]]; then
    echo "Tentative de résolution des problèmes de paquets existants..."

    # 1. Mettre à jour et installer les outils de base
    apt-get update
    apt-get install -y curl openssh-client git

    # 2. Supprimer l'ancien dépôt NodeSource si existant (pour qu'il soit recréé proprement)
    echo "Suppression des anciens dépôts NodeSource si présents..."
    sudo rm -f /etc/apt/sources.list.d/nodesource.list*
    sudo apt-get update > /dev/null 2>&1 || true

    # 3. Ajouter le dépôt NodeSource et installer Node.js LTS
    echo "Ajout du dépôt NodeSource et installation de Node.js LTS..."
    # Exécuter la commande setup_lts.x qui va configurer le dépôt
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -

    # Tenter de corriger les dépendances et installer Node.js et NPM
    # Utiliser 'apt-get dist-upgrade' avant 'apt-get install' pour une meilleure résolution des dépendances
    echo "Tenter de résoudre les paquets cassés et installer Node.js/NPM..."
    sudo apt-get update # Mettre à jour après l'ajout du nouveau dépôt
    sudo dpkg --configure -a || true # Reconfigure les paquets non configurés
    sudo apt-get install -f -y || true # Tente de résoudre les dépendances manquantes
    sudo apt-get dist-upgrade -y || true # Met à niveau le système, peut aider à résoudre les conflits
    
    # Installer Node.js et NPM (npm est une dépendance de nodejs sur NodeSource)
    # Utilisation de 'apt-get install --reinstall' si nodejs/npm sont déjà là mais cassés
    apt-get install -y nodejs npm || {
        echo "L'installation initiale de Node.js/NPM a échoué. Tentative de réinstallation..."
        apt-get install --reinstall -y nodejs npm || {
            echo "Échec de la réinstallation de Node.js/NPM. La commande APT a signalé une erreur. Cela pourrait indiquer un conflit irréversible sans purge."
            echo "Veuillez vérifier les paquets manuellement (ex: 'dpkg -l | grep node' ou 'apt-cache policy nodejs')."
            exit 1
        }
    }

    # Vérification finale de Node.js et NPM
    if ! command -v node &> /dev/null || ! command -v npm &> /dev/null; then
        echo "Erreur critique: Node.js ou NPM n'a pas pu être installé ou trouvé dans le PATH après l'installation. Arrêt du script."
        exit 1
    fi
    echo "Node.js et NPM installés avec succès."

elif [[ "$OS" == "centos" || "$OS" == "rhel" ]]; then
    echo "Installation des dépendances pour CentOS/RHEL..."
    yum install -y curl openssh-clients git
    curl -fsSL https://rpm.nodesource.com/setup_lts.x | bash -
    yum install -y nodejs npm
else
    echo "Installation de Node.js non prise en charge pour cette distribution. Veuillez installer manuellement Node.js, NPM, PM2 et Git."
    exit 1
fi

# PM2 est installé après Node.js/NPM, car il dépend d'eux
echo "Installation de PM2..."
npm install -g pm2 || { echo "Échec de l'installation de PM2. Arrêt du script."; exit 1; }
echo "Dépendances essentielles installées."

# --- 2. Création du répertoire de l'agent et clonage du dépôt GitHub ---
echo "2. Création du répertoire de l'agent et clonage du dépôt GitHub..."
AGENT_INSTALL_DIR="/opt/vps-agent"
mkdir -p "$AGENT_INSTALL_DIR"
cd "$AGENT_INSTALL_DIR" || { echo "Échec de cd vers $AGENT_INSTALL_DIR. Arrêt du script."; exit 1; }

# Cloner le dépôt et copier les fichiers de l'agent au bon endroit
git clone "$AGENT_REPO_URL" temp_repo_clone || { echo "Échec du clonage du dépôt Git. Arrêt du script."; exit 1; }

# Vérifier si AGENT_DIR_IN_REPO est vide ou non
if [ -z "$AGENT_DIR_IN_REPO" ]; then
    echo "Copiage des fichiers de l'agent depuis la racine du dépôt cloné..."
    cp -r temp_repo_clone/* . || { echo "Échec de la copie des fichiers de l'agent. Arrêt du script."; exit 1; }
else
    echo "Copiage des fichiers de l'agent depuis le sous-dossier '$AGENT_DIR_IN_REPO' du dépôt cloné..."
    if [ ! -d "temp_repo_clone/$AGENT_DIR_IN_REPO" ]; then
        echo "Erreur: Le sous-dossier de l'agent '$AGENT_DIR_IN_REPO' n'existe pas dans le dépôt cloné. Veuillez vérifier AGENT_DIR_IN_REPO."
        exit 1
    fi
    cp -r temp_repo_clone/"$AGENT_DIR_IN_REPO"/* . || { echo "Échec de la copie des fichiers de l'agent. Arrêt du script."; exit 1; }
fi

rm -rf temp_repo_clone # Nettoyer le dépôt cloné temporaire

echo "Fichiers de l'agent téléchargés depuis GitHub."

# --- 3. Installation des dépendances NPM de l'agent ---
echo "3. Installation des dépendances NPM de l'agent..."
if [ -f package.json ]; then
    npm install --production || { echo "Échec de l'installation des dépendances NPM. Arrêt du script."; exit 1; }
else
    echo "Avertissement: Aucun fichier package.json trouvé dans '$AGENT_INSTALL_DIR'. Aucune dépendance NPM à installer."
fi
echo "Dépendances NPM installées (si package.json existait)."

# --- 4. Configuration de l'agent (fichier .env) ---
echo "4. Configuration de l'agent..."
if [ -z "$API_SECRET_FOR_AGENT" ] || [ -z "$VPS_IDENTIFIER" ]; then
    echo "Erreur: API_SECRET_FOR_AGENT ou VPS_IDENTIFIER sont manquants. L'agent ne sera pas configuré correctement."
    exit 1
fi
echo "API_SECRET=$API_SECRET_FOR_AGENT" > .env
echo "PORT=$AGENT_PORT" >> .env
echo "Fichier .env créé pour l'agent."

# --- 5. Démarrage de l'Agent Node.js (écoute sur localhost) ---
echo "5. Lancement de l'Agent Node.js avec PM2..."
pm2 start agent.js --name vps-agent -- restart-delay 5000 || { echo "Échec du démarrage de l'agent Node.js avec PM2. Arrêt du script."; exit 1; }
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


# --- 8. Démarrage du tunnel SSH inversé avec PM2 ---
echo "8. Lancement du tunnel SSH inversé avec PM2..."
PM2_TUNNEL_ARGS="-N -T -R 0.0.0.0:$TUNNEL_PORT:localhost:$AGENT_PORT -i $SSH_KEY_PATH -o ExitOnForwardFailure=yes -o ServerAliveInterval=60 -o ServerAliveCountMax=3 $SSH_TUNNEL_USER@$YOUR_BACKEND_IP"
pm2 start ssh --name vps-tunnel -- "$PM2_TUNNEL_ARGS" || { echo "Échec du démarrage du tunnel SSH. Arrêt du script."; exit 1; }
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