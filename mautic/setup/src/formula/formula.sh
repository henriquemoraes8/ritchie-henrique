#!/bin/sh
runFormula() {
  # Check Docker
  if ! [ -x "$(command -v docker)" ]; then
    echo 'No docker detected, installing...'

    sudo apt-get update -qq >/dev/null
    sudo apt-get install -qq -y apt-transport-https

    sudo wget -nv -O - https://get.docker.com/ | sh
  fi

  # Check dokku
  if ! [ -x "$(command -v dokku)" ]; then
    echo 'No dokku detected, installing...'

    wget https://raw.githubusercontent.com/dokku/dokku/v0.21.4/bootstrap.sh;
    sudo DOKKU_TAG=v0.21.4 bash bootstrap.sh
  fi

  # Deploy Mautic
  if [ $(dokku apps:create mautic) ]
  then
    # create storage for the app
    mkdir $PROJECT
    chown -R dokku:dokku $PROJECT
    dokku storage:mount app-name $PROJECT:/var/lib/mysql

    docker pull mautic/mautic:v3
    docker tag mautic/mautic:v3 dokku/mautic:v3
    dokku tags:deploy dokku/mautic v3
  fi

  # db setup
  sudo dokku plugin:install https://github.com/dokku/dokku-mysql.git mysql
  DB_NAME="${PROJECT}_db"
  DB_DSN=$(dokku mysql:create $DB_NAME | grep Dsn)
  if [ $? -eq 0 ]
  then
    HOST_NAME=$(echo $DB_DNS | cut -d @ -f 2 | cut -d / -f 1)
    PASSWORD=$(echo $DB_DNS | cut -d @ -f 1 | cut -d : -f 4)
    dokku config:set mautic MAUTIC_DB_HOST=$HOST_NAME MAUTIC_DB_USER=mysql MAUTIC_DB_PASSWORD=$PASSWORD MAUTIC_DB_NAME=$DB_NAME
  fi

  IP=$(hostname -i | cut ifdata -pa br0-d " " -f 1)

  case $CONNECTION in
        port )
          read -p "Specify the port you wish to expose: " PORT
          dokku proxy:ports-add $PROJECT http:8080:3306
          echo "All set! You can acces your app at $IP:$PORT"
          break;;
        domain )
          read -p "Specify the domain you would like to use (i.e.: your.domain.com): " DOMAIN
          dokku domains:add $PROJECT $DOMAIN
          echo "All set! You can acces your app at $DOMAIN"
          break;;
        ssl )
          read -p "Specify the domain you would like to use and make sure the A record is set (i.e.: your.domain.com): " DOMAIN
          read -p "Provide an email for letsencrypt: " EMAIL
          dokku domains:add $PROJECT $DOMAIN
          sudo dokku plugin:install https://github.com/dokku/dokku-letsencrypt.git
          dokku config:set --no-restart $PROJECT DOKKU_LETSENCRYPT_EMAIL=$EMAIL
          dokku letsencrypt mautic
          dokku letsencrypt:cron-job --add
          echo "All set! You can acces your https app at $DOMAIN"
          break;;
  esac

  printf "\n\nWARNING: if this is your first time setting up, you should visit $IP to set your ssh keys and prevent your machine from being exposed"
}
