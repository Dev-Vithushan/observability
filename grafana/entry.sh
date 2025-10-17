cat /credentials/creds | grep -v '^#' | tr '\n' '\0' | xargs -0 -n 1 bash /scripts/create-user.sh > /tmp/user-creation.log
