# Make hash of password for Dex
PASS='password'
htpasswd -BnBC 10 "" "$PASS" | tr -d ':\n'
echo
