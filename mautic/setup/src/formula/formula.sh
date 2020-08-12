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

  # db setup
  if ! dokku mysql > /dev/null 2>&1; then
    sudo dokku plugin:install https://github.com/dokku/dokku-mysql.git mysql
  fi
  DB_NAME="${PROJECT}_db"
  dokku mysql:create $DB_NAME
  echo "Successfully setup $DB_NAME database"
  DB_DSN=$(dokku mysql:info $DB_NAME | grep Dsn)
  HOST_NAME=$(echo $DB_DSN | cut -d @ -f 2 | cut -d / -f 1)
  PASSWORD=$(echo $DB_DSN | cut -d @ -f 1 | cut -d : -f 4)

  # Deploy Mautic
  if dokku apps:create $PROJECT > /dev/null 2>&1; then
    # create storage for the app
    mkdir $PROJECT
    chown -R dokku:dokku $PROJECT

    dokku mysql:link $DB_NAME $PROJECT
    dokku config:set $PROJECT MAUTIC_DB_HOST=$HOST_NAME MAUTIC_DB_USER=mysql MAUTIC_DB_PASSWORD=$PASSWORD MAUTIC_DB_NAME=$DB_NAME MAUTIC_RUN_CRON_JOBS=true

    docker pull mautic/mautic:v3
    docker tag mautic/mautic:v3 dokku/$PROJECT:latest
    dokku tags:deploy $PROJECT latest
    dokku storage:mount $PROJECT ~/$PROJECT:/var/lib/mysql
    echo "Successfully created $PROJECT app"
  else
    echo "Project $PROJECT already found, skipping app creation"
  fi

  IP=$(hostname -I | cut -d " " -f 1)

  echo
  case $CONNECTION in
        port )
          read -p "Specify the port you wish to expose: " PORT
          dokku proxy:ports-add $PROJECT http:$PORT:3306
          echo "All set! You can acces your app at $IP:$PORT"
          ;;
        domain )
          read -p "Specify the domain you would like to use (i.e.: your.domain.com): " DOMAIN
          dokku domains:add $PROJECT $DOMAIN
          echo "All set! You can acces your app at $DOMAIN"
          ;;
        ssl )
          read -p "Specify the domain you would like to use and make sure the A record is set (i.e.: your.domain.com): " DOMAIN
          read -p "Provide an email for letsencrypt: " EMAIL
          dokku domains:add $PROJECT $DOMAIN

          if ! dokku letsencrypt > /dev/null 2>&1; then
            sudo dokku plugin:install https://github.com/dokku/dokku-letsencrypt.git
          fi

          dokku config:set --no-restart $PROJECT DOKKU_LETSENCRYPT_EMAIL=$EMAIL
          dokku letsencrypt $PROJECT
          dokku letsencrypt:cron-job --add
          echo "All set! You can acces your https app at $DOMAIN"
          ;;
  esac

  printf "\nWARNING: if this is your first time setting up, you should visit $IP to set your ssh keys and prevent your machine from being exposed\n\n"
}
