#!/bin/bash

# © 2018 zekro Development
# contact[at]zekro.de | https://zekro.de

# MIT License

# Copyright (c) 2018 Ringo Hoffmann (zekro Development)

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

########################################################################

_VERSION="1.1.0"

# COLOR CODES
_RED="\033[0;31m"
_CYAN="\033[0;36m"
_NC="\033[0m"

# STATICS
_CFG="config.cfg"

function logerr {
    printf "${_RED}ERROR${_NC} | $1\n"
}

function loginfo {
    printf "${_CYAN}INFO${_NC}  | $1\n"
}

function checkcmd {
    if [ "$(command -v $1)" == "" ]; then
        logerr "Command $1 does not exist or is not available for this user."
        exit 1
    fi
}

function checkconfig {
    if [ "$TIMER" == "" ]; then
        logerr "Config var TIMER is empty."
        exit 1
    fi

    if [ "$DB_ADDRESS" == "" ]; then
        logerr "Config var DB_ADDRESS is empty."
        exit 1
    fi

    if [ "$DB_USERNAME" == "" ]; then
        logerr "Config var DB_USERNAME is empty."
        exit 1
    fi

    if [ "$DB_PASSWORD" == "" ]; then
        logerr "Config var DB_PASSWORD is empty."
        exit 1
    fi

    if [ "$REPOS" == "" ]; then
        logerr "Config var REPOS is empty."
        exit 1
    fi
}

function dumpdb {
    loginfo "Dumping database ${1}..."
    mysqldump -h $DB_ADDRESS -u $DB_USERNAME \
        --password=$DB_PASSWORD ${1} > ./.tmp/${1}.sql
}

function makebackup {
    loginfo "Collecting MySql dump... This process can take up a while..."

    if ! [ -d ./.tmp ]; then
        mkdir ./.tmp
    fi

    __WL=false
    if ! [ "$WHITELIST" == "" ]; then
        databases=$(mysql -h $DB_ADDRESS -u $DB_USERNAME --password=$DB_PASSWORD -e "SHOW DATABASES;")
        __WL=true
    else 
        databases=$(mysql -h $DB_ADDRESS -u $DB_USERNAME --password=$DB_PASSWORD -e "SHOW DATABASES;" | grep -Ev "(Database|information_schema|performance_schema)")
    fi
    

    for database in ${databases}; do
        $__WL && {
            echo $database | grep -E "$WHITELIST" > /dev/null && {
                dumpdb $database
            }
        } || {
            __ENABLED=true
            if [ "$BLACKLIST" == "" ]; then
                __ENABLED=false
            fi
            ($__ENABLED && echo $database | grep -E "$BLACKLIST" > /dev/null) || {
                dumpdb $database
            }
        }
    done

    for repo in ${REPOS[*]}; do
        __existing=true
        IFS='/' read -ra reposplit <<< "$repo"
        lastindex=$(( ${#reposplit[*]} - 1 ))
        reponame=${reposplit[$lastindex]}
        if ! [ -d $reponame ]; then
            loginfo "${reponame} does not exists locally and will be cloned..."
            {
                git clone $repo ./$reponame
            } || {
                logerr "Could not clone repo ${repo}. Skipping..."
                __existing=false
            }
        fi
        if $__existing; then
            cp ./.tmp/. ./${reponame}/dumps -R
            cd ./${reponame}
            git add .
            git -c user.name="mySqlBackup" -c user.email="mySqlBackup" \
                commit -m "MySqlbackup: $(date +"%Y-%m-%d %H:%M:%S")"
            git push -u origin master
            cd ..
        fi
    done

    rm -f -r ./.tmp
}

########################################################################

# CHECK FOR MYSQLDUMP, GIT
checkcmd "mysqldump"
checkcmd "mysql"
checkcmd "git"

# CHECK FOR COMMAND LINE ARGS
POSITIONAL=()
while (( $# > 0 )); do
    key=$1
    case $key in

        "-c"|"--config")
        ARG_CONF=$2
        shift; shift
        ;;

        *)
        POSITIONAL+=($1)
        shift
        ;;

    esac
done
set -- ${POSITIONAL[@]}

if ! [[ "$ARG_CONF" == "" ]]; then
    _CFG=$ARG_CONF
fi

loginfo "=================================="
loginfo "MySqlBackup.sh v.${_VERSION}"
loginfo "© 2018 zekro Development"
loginfo "github.zekro.de/MySqlBackup.sh"
loginfo "=================================="

# CHECK FOR CONFIG AND CREATE IF NOT EXISTENT
if ! [ -f $_CFG ]; then
    echo \
"# Timer delay in seconds. Defaultly set to 1 day (60s*60*24).
# If you set this to 0, the backup will only be executed once
# (for example for usage with chron).
TIMER=86400

# Enter repository/repositories where the backups will be pushed
# to. This is in form of an array defined like following:
# ('/path/to/repo/1.git' 'git@mysite.com:my/repo.git')
REPOS=()

# Here you can enter databases which should be ignored for the
# backup script in form of an regular expression.
# For example: '(db1|db2|db3)'
BLACKLIST=

# Here you can enter exclusively which databases should be
# backuped. If tehere are entries here, property BLACKLIST
# will be ignored. Here also in form of a regular expression.
WHITELIST=

# Enter here your database login credentials:
DB_ADDRESS=
DB_USERNAME=
DB_PASSWORD=" > $_CFG
    logerr "${_CFG} missing and got created. Edit it and continue."
    exit 1
fi

# LOAD CONFIG
loginfo "Loading config..."
source $_CFG
checkconfig

mysql -h $DB_ADDRESS -u $DB_USERNAME \
    --password=$DB_PASSWORD -e "SHOW DATABASES;" \
    > /dev/null

loginfo "Successfully connected to database. Cedentials are correct."

if [ $TIMER == 0 ]; then
    loginfo "INITIATING BACKUP ONCE"
    loginfo "======================"
    makebackup
    exit 0
fi

while true; do
    loginfo "INITIATING BACKUP"
    loginfo "================="

    makebackup

    loginfo "==============="
    loginfo "BACKUP FINISHED"
    loginfo "==============="
    sleep $TIMER
done
