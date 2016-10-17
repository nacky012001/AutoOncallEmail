BASEDIR=$(dirname "$0")
. /opt/deploy/env/ruby-1.9.3/.envrc
ruby "$BASEDIR/send_oncall_email.rb"
