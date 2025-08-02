# Utilise une image Node.js LTS officielle comme base
FROM node:lts-slim

# Update system packages to address vulnerabilities
RUN apt-get update && apt-get upgrade -y && apt-get clean && rm -rf /var/lib/apt/lists/*

# Définit le répertoire de travail à l'intérieur du conteneur
WORKDIR /app

# Copie package.json et package-lock.json pour installer les dépendances
# Ceci optimise le cache Docker: les dépendances ne sont réinstallées que si ces fichiers changent
COPY package*.json ./

# Installe les dépendances NPM
RUN npm install --production

# Copie le reste du code de l'application
COPY . .

# Expose le port sur lequel votre agent écoute à l'intérieur du conteneur
# C'est le PORT de votre agent Node.js (ex: 3001)
EXPOSE 3001

# Commande pour démarrer l'agent quand le conteneur est lancé
CMD [ "node", "agent.js" ]