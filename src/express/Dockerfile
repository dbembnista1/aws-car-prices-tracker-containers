# Używamy oficjalnego obrazu Node.js (wersja slim dla mniejszego rozmiaru)
FROM node:20-slim

# Instalujemy zależności systemowe niezbędne dla biblioteki 'canvas'
# Są one wymagane, ponieważ 'canvas' kompiluje się z natywnych bibliotek C++
RUN apt-get update && apt-get install -y \
    build-essential \
    libcairo2-dev \
    libpango1.0-dev \
    libjpeg-dev \
    libgif-dev \
    librsvg2-dev \
    && rm -rf /var/lib/apt/lists/*

# Tworzymy katalog roboczy wewnątrz kontenera
WORKDIR /usr/src/app

# Kopiujemy pliki definicji zależności
COPY package*.json ./

# Instalujemy zależności (produkcyjne)
RUN npm install --only=production

# Kopiujemy resztę kodu aplikacji
COPY . .

# Informujemy, że kontener nasłuchuje na porcie 3000
EXPOSE 3000

# Komenda uruchamiająca aplikację
CMD [ "npm", "start" ]
