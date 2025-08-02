#!/bin/bash

# --- Configuration ---
AGENT_VERSION="1.0.0"
AGENT_FILE_URL="https://votre-domaine.com/path/to/agent.js" # URL directe de votre agent.js
AGENT_PORT="3001" # Port sur lequel l'agent écoute en LOCAL sur le VPS (127.0.0.1)

# Informations de votre serveur principal (backend) pour le tunnel
YOUR_BACKEND_IP="VOTRE_IP_PUBLIQUE_DU_BACKEND"
SSH_TUNNEL_USER="tunnel_user"
TUNNEL_PORT="10000" # Port sur VOTRE BACKEND que le tunnel va créer (choisissez un port non utilisé et au-dessus de 1024)

# Récupérer l'API_SECRET et le PUBLIC_KEY_FOR_TUNNEL (si générée par votre backend)
# OU API_SECRET_PASSED_BY_CURL="$1" si vous passez la clé secrète via la commande curl
# Et la clé publique sera générée sur le VPS et envoyée à votre backend via une requête POST.

LOG_FILE="/var/log/vps-agent-setup.log"
exec > >(tee -a ${LOG_FILE}) 2>&1
echo "--- Début du processus d'installation de l'agent VPS avec tunnel SSH ---"
echo "Date: $(date)"

# --- Vérifier les privilèges root et OS (comme dans l'exemple précédent) ---
if [ "$EUID" -ne 0 ]; then echo "Ce script doit être exécuté avec les privilèges root."; exit 1; fi
# (Inclure ici la détection OS et installation de Node.js, NPM, PM2, comme dans l'exemple précédent)

# --- 1. Installation de OpenSSH Client (si ce n'est pas déjà fait) ---
echo "1. Installation de OpenSSH Client..."
if [[ "$OS" == "debian" || "$OS" == "ubuntu" ]]; then
    apt-get update && apt-get install -y openssh-client
elif [[ "$OS" == "centos" || "$OS" == "rhel" ]]; then
    yum install -y openssh-clients
fi
echo "OpenSSH Client installé."
    
# --- 2. Création du répertoire de l'agent et téléchargement (comme avant) ---
echo "2. Création du répertoire de l'agent et téléchargement..."
AGENT_DIR="/opt/vps-agent"
mkdir -p "$AGENT_DIR"
cd "$AGENT_DIR" || exit 1
wget -O agent.js "$AGENT_FILE_URL" || { echo "Échec du téléchargement de agent.js"; exit 1; }
# (Installer les dépendances NPM si votre agent en a)

# --- 3. Configuration de l'agent (fichier .env) ---
echo "3. Configuration de l'agent..."
# L'API_SECRET sera passée à l'agent via le .env ou via une variable d'environnement PM2
# Si l'API_SECRET est passée via la commande curl:
API_SECRET_FOR_AGENT="$1" # Premier argument du script
echo "API_SECRET=$API_SECRET_FOR_AGENT" > .env
echo "PORT=$AGENT_PORT" >> .env # L'agent écoutera sur ce port LOCALEMENT
echo "Fichier .env créé pour l'agent."

# --- 4. Démarrage de l'Agent Node.js (écoute sur localhost) ---
echo "4. Lancement de l'Agent Node.js..."
# L'agent doit écouter sur localhost, pas 0.0.0.0
# Dans votre `agent.js` : app.listen(PORT, '127.0.0.1', () => {...});
pm2 start agent.js --name vps-agent -- restart-delay 5000
pm2 save
echo "Agent VPS lancé avec PM2."

# --- 5. Génération de la paire de clés SSH pour le tunnel ---
echo "5. Génération de la paire de clés SSH pour le tunnel..."
SSH_KEY_PATH="$HOME/.ssh/id_rsa_vps_tunnel" # Clé stockée dans le home de l'utilisateur root
ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" # Pas de passphrase
chmod 600 "$SSH_KEY_PATH"
chmod 600 "$SSH_KEY_PATH.pub"

# Récupérer la clé publique
PUBLIC_KEY_FOR_TUNNEL=$(cat "$SSH_KEY_PATH.pub")
echo "Clé publique du tunnel générée: $PUBLIC_KEY_FOR_TUNNEL"

# --- 6. Envoi de la Clé Publique à votre Backend ---
# C'est la partie CRUCIALE pour l'automatisation.
# L'agent OU le script de setup doit envoyer cette clé publique à votre backend.
# Votre backend doit avoir un endpoint pour recevoir ces clés et les ajouter au authorized_keys de tunnel_user.
# Vous aurez besoin de l'ID du VPS ou d'un identifiant unique pour que votre backend sache à quel VPS cette clé appartient.

VPS_IDENTIFIER="UNIQUE_ID_POUR_CE_VPS" # Vous devez générer/passer cet ID
BACKEND_API_URL="https://votre-domaine.com/api/register-tunnel-key"
# L'API_SECRET utilisée ici est celle passée via curl, elle authentifie cette requête initiale
AUTH_TOKEN=$(echo -n "$API_SECRET_FOR_AGENT" | sha256sum | awk '{print $1}') # Hachage simple

echo "Envoi de la clé publique à votre backend..."
curl -X POST \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer $AUTH_TOKEN" \
     -d "{\"vpsId\": \"$VPS_IDENTIFIER\", \"publicKey\": \"$PUBLIC_KEY_FOR_TUNNEL\"}" \
     "$BACKEND_API_URL" || { echo "Échec de l'envoi de la clé publique au backend. Le tunnel ne fonctionnera pas."; exit 1; }
echo "Clé publique envoyée au backend."

# --- 7. Démarrage du tunnel SSH inversé avec PM2 ---
echo "7. Lancement du tunnel SSH inversé..."
# Utilisez pm2 start ssh -- -- pour passer des arguments à la commande ssh
# -N: Ne pas exécuter de commande distante
# -T: Désactiver l'allocation de pseudo-terminal
# -R <port_backend>:localhost:<port_agent_local> : Redirection inversée
# -i <chemin_cle_privee> : Spécifier la clé privée
# -o ExitOnForwardFailure=yes : Quitter si la redirection échoue
# -o ServerAliveInterval=60 -o ServerAliveCountMax=3 : Pour maintenir la connexion en vie
PM2_TUNNEL_ARGS="-N -T -R 0.0.0.0:$TUNNEL_PORT:localhost:$AGENT_PORT -i $SSH_KEY_PATH -o ExitOnForwardFailure=yes -o ServerAliveInterval=60 -o ServerAliveCountMax=3 $SSH_TUNNEL_USER@$YOUR_BACKEND_IP"
pm2 start ssh --name vps-tunnel -- "$PM2_TUNNEL_ARGS"
pm2 save
pm2 startup systemd # Assure que PM2 et ses processus (agent, tunnel) démarrent au boot

echo "Tunnel SSH inversé lancé avec PM2 et configuré pour démarrer au boot."

echo "--- Processus d'installation terminé ! ---"
echo "Vérifiez les logs dans ${LOG_FILE}"
echo "Statut de l'agent PM2: pm2 status vps-agent"
echo "Statut du tunnel PM2: pm2 status vps-tunnel"