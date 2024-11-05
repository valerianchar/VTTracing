#!/bin/bash

unameOut="$(uname -s)"
case "${unameOut}" in
    Linux*)     machine=Linux;;
    Darwin*)    machine=Mac;;
    CYGWIN*)    machine=Cygwin;;
    MINGW*)     machine=MinGw;;
    *)          machine="UNKNOWN:${unameOut}"
esac

if [ ${machine} == MinGw ] ; then
    echo "MinGw"
    dc() {
        winpty docker compose "$@"
    }
else
    dc() {
        # echo "=> docker compose $@"
        COMPOSE_DOCKER_CLI_BUILD=1 DOCKER_BUILDKIT=1 docker compose "$@"
    }
fi
export -f dc
# alias docker="winpty docker"
# alias docker-compose="winpty docker-compose"

# prints colored text
print_style () {

    if [ "$2" == "info" ] ; then
        COLOR="96m"
    elif [ "$2" == "success" ] ; then
        COLOR="92m"
    elif [ "$2" == "warning" ] ; then
        COLOR="93m"
    elif [ "$2" == "danger" ] ; then
        COLOR="91m"
    else #default color
        COLOR="0m"
    fi

    STARTCOLOR="\e[$COLOR"
    ENDCOLOR="\e[0m"

    printf "$STARTCOLOR%b$ENDCOLOR" "$1"
}

display_options () {
    printf "Available options:\n";
    print_style "   bash" "success"; printf "\t\t\t Open bash on the workspace with user laradock.\n"
    print_style "   build [services]" "success"; printf "\t Build containers.\n"
    print_style "   cinstall" "success"; printf "\t\t Composer install vendors (Rather than update).\n"
    print_style "   clearl" "success"; printf "\t\t Clear logs.\n"
    print_style "   clearq" "success"; printf "\t\t Clear queue.\n"
    print_style "   crequire" "success"; printf "\t\t Composer require new packages.\n"
    print_style "   cupdate" "success"; printf "\t\t Composer update vendors (Be careful, updates may break code).\n"
    print_style "   down" "success"; printf "\t\t\t Stop containers\n"
    print_style "   hot" "success"; printf "\t\t\t Compile and recompile js files when they are updated.\n"
    print_style "   install" "success"; printf "\t\t Install locked node and composer dependencies.\n"
    print_style "   reload [services]" "success"; printf "\t Reload containers.\n"   
    print_style "   reset [services]" "success"; printf "\t Reset containers and folders.\n"
    print_style "   root" "success"; printf "\t\t\t Open bash on the workspace with user root.\n"
    print_style "   seed" "success"; printf "\t\t\t Seed database.\n"
    print_style "   setup" "success"; printf "\t\t Setup the project for the first time.\n"
    print_style "   test" "success"; printf "\t\t\t Run tests.\n"
    print_style "   up [services]" "success"; printf "\t Run docker compose.\n"
}

if [[ $# -eq 0 ]] ; then
    print_style "Missing arguments.\n" "danger"
    display_options
    exit 1
fi

FILE=.env
if [ ! -f "$FILE" ]; then
    print_style ".env file does not exist.\n" "danger"
    print_style "Please copy .env.example to .env\n" "warning"
    print_style "Then change .env as needed.\n" "warning"
    print_style "cp .env.example .env\n" "info"
    exit 1
fi

dc_exec() {
    dc exec --user=laradock workspace "$@"
}

dc_up_no_mysql() {
    print_style "Initializing Docker Compose up\n" "info"
    dc up -d nginx php-worker phpmyadmin
}
export -f dc_up_no_mysql

dc_up() {
    dc_up_no_mysql mysql "$@"
}
export -f dc_up

dc_down() {
    print_style "Stopping Docker compose\n" "info"
    dc stop php-worker
    dc stop nginx php-fpm
    dc down
}
export -f dc_down

clearlogs() {
    print_style "Clear logs\n" "info"
    dc_exec bash -c "rm -f storage/logs/*.log"
}
export -f clearlogs

clearqueue(){
    print_style "Clear queue\n" "info"
    dc_exec php artisan queue:restart
}
export -f clearqueue

cinstall() {
    print_style "Initializing composer install\n" "info"    
    dc_exec composer config process-timeout 2000
    dc_exec composer check-platform-reqs
    dc_exec composer install
}
export -f cinstall

node_install() {
    print_style "Install node packages\n" "info"
    dc_exec npm ci --cache .npm --prefer-offline
}
export -f cinstall

seed() {
    print_style "Seeding\n" "info"
    dc_exec php artisan db:seed "$@"
}
export -f seed

dc_test() {
    dc_up_no_mysql
    print_style "Restart Mysql in memory container.\n" "info"
    dc stop mysql-ram
    dc up -d mysql-ram
    dc_exec ./waitfor.sh --database=mysql-ram
    print_style "Run tests.\n" "info"
    dc_exec php artisan test $@
}
export -f dc_test

dc_wait_mysql() {
    dc exec workspace chmod +x ./waitfor.sh
    dc_exec ./waitfor.sh
}
export -f dc_wait_mysql

if [ "$1" == "up" ] ; then
    shift # removing first argument
    dc_up ${@}

elif [ "$1" == "down" ]; then
    dc_down

elif [ "$1" == "seed" ]; then
    shift # removing first argument
    seed ${@}

elif [ "$1" == "build" ]; then
    dc_down
    shift # removing first argument
    set -e
    dc build --no-cache docker-in-docker nginx workspace php-fpm php-worker redis mysql mysql-ram ${@}

elif [ "$1" == "reload" ]; then
    dc_down
    shift # removing first argument
    dc_up ${@}

elif [ "$1" == "install" ]; then
    cinstall
    node_install

elif [ "$1" == "reset" ]; then
    clearlogs
    dc_down
    shift # removing first argument
    set -e
    print_style "Start Project\n" "info"
    dc up -d nginx mysql redis minio mailcatcher phpmyadmin ${@}
    print_style "Clear Minio data bucket\n" "info"
    dc exec minio rm -rf /export/local
    print_style "Set up new Minio data bucket\n" "info"
    dc exec minio mkdir -p /export/local
    print_style "Rechargement de la config\n" "info"
    dc_exec php artisan config:clear

    dc_wait_mysql

    print_style "Reset database\n" "info"
    dc_exec php artisan migrate:fresh
    print_style "Start workers\n" "info"
    dc up -d php-worker
    print_style "Set perms\n" "info"
    dc exec workspace chmod -R 777 storage
    dc exec workspace chmod -R 777 bootstrap
    clearqueue

    print_style "Cache views\n" "info"
    dc_exec php artisan view:cache

    print_style "Build js\n" "info"
    dc_exec npm run build

    seed

elif [ "$1" == "setup" ]; then
    clearlogs
    dc_down
    shift # removing first argument
    set -e
    FILE=../app/.env
    if [ ! -f "$FILE" ]; then
        print_style "Project ../app/.env file does not exist.\n" "danger"
        print_style "Please copy .env.example to .env\n" "warning"
        print_style "Then change .env as needed.\n" "warning"
        print_style "cp ../app/.env.example ../app/.env\n" "info"
        exit 1
    fi
    print_style "Start Project\n" "info"
    dc up -d docker-in-docker nginx workspace php-fpm mysql phpmyadmin ${@}
    print_style "Set up minio data bucket\n" "info"
    dc exec minio mkdir -p /export/local
    print_style "Set perms\n" "info"
    dc exec workspace chmod -R 777 storage
    dc exec workspace chmod -R 777 bootstrap

    cinstall

    print_style "Rechargement de la config\n" "info"
    dc_exec php artisan config:clear

    dc_wait_mysql

    print_style "Reset database\n" "info"
    dc_exec php artisan migrate:fresh
    
    print_style "Setup workers\n" "info"
    sed 's/numprocs=8/numprocs=1/g' php-worker/supervisord.d/laravel-worker.conf.example > php-worker/supervisord.d/laravel-worker.conf

    print_style "Start workers\n" "info"
    dc up -d php-worker

    clearqueue

    node_install

    print_style "Cache views\n" "info"
    dc_exec php artisan view:cache

    print_style "Build js\n" "info"
    dc_exec npm run build

    seed

elif [ "$1" == "clearl" ]; then
    clearlogs

elif [ "$1" == "clearq" ]; then
    clearqueue

elif [ "$1" == "bash" ]; then
    dc_exec bash

elif [ "$1" == "zsh" ]; then
    dc_exec zsh

elif [ "$1" == "root" ]; then
    dc exec workspace bash

elif [ "$1" == "hot" ]; then
    print_style "Run 'yarn hot'\n" "success"
    dc_exec yarn dev

elif [ "$1" == "test" ]; then
    shift
    dc_test ${@}

elif [ "$1" == "cupdate" ]; then
    print_style "Initializing composer update\n" "info"
    dc_exec composer config process-timeout 2000
    dc_exec composer check-platform-reqs
    dc_exec composer update

elif [ "$1" == "cinstall" ]; then
    cinstall

elif [ "$1" == "crequire" ] ; then
    print_style "Initializing composer require\n" "info"
    shift # removing first argument
    dc_exec composer config process-timeout 2000
    dc_exec composer require ${@}

else
    print_style "Invalid arguments.\n" "danger"
    display_options
    exit 1
fi
