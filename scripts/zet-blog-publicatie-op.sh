#!/usr/bin/env bash
# Eenmalig inrichten van het automatisch publiceren van de blog.
# Draai dit vanaf de Mac van Elio (nodig: ssh-toegang tot de server en `gh`).
#
# Wat het doet:
#   1. maakt een NIEUWE sleutel, alleen voor deze taak (de privé-helft staat
#      daarna alleen nog als geheim in GitHub; lokaal wordt hij gewist)
#   2. zet de publieke helft op de server, begrensd tot schrijven binnen de
#      map van deze site: geen shell, geen doorsturen, geen andere mappen
#   3. maakt in GitHub de omgeving "productie" die alleen de tak main toelaat,
#      en zet daar de sleutel en de vastgepinde serveridentiteit in
#
# Intrekken:  scripts/zet-blog-publicatie-op.sh --intrekken
set -euo pipefail

REPO="${REPO:-payiban/conti-nu-website}"
SSH_DOEL="${SSH_DOEL:-vps-marketing}"          # alias uit ~/.ssh/config
SERVER_HOST="${SERVER_HOST:-149.210.189.167}"
SERVER_USER="${SERVER_USER:-tagliola}"
SITE_PAD="${SITE_PAD:-/var/www/conti-nu.nl}"
OMGEVING="productie"
MERK="github-actions blog conti-nu"

verwijder_oude_sleutel() {
  ssh "$SSH_DOEL" "test -f ~/.ssh/authorized_keys && grep -vF '$MERK' ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.nieuw && cat ~/.ssh/authorized_keys.nieuw > ~/.ssh/authorized_keys && rm ~/.ssh/authorized_keys.nieuw || true"
}

if [ "${1:-}" = "--intrekken" ]; then
  verwijder_oude_sleutel
  gh secret delete BLOG_DEPLOY_KEY --env "$OMGEVING" --repo "$REPO" || true
  echo "Ingetrokken: de sleutel staat niet meer op de server en niet meer in GitHub."
  exit 0
fi

echo "1/4  Server controleren…"
wie=$(ssh "$SSH_DOEL" whoami)
[ "$wie" = "$SERVER_USER" ] || { echo "Verwacht gebruiker $SERVER_USER, kreeg $wie." >&2; exit 1; }
ssh "$SSH_DOEL" "test -w '$SITE_PAD'" || { echo "$SERVER_USER kan niet schrijven in $SITE_PAD." >&2; exit 1; }
RRSYNC=$(ssh "$SSH_DOEL" 'command -v rrsync || ls /usr/share/doc/rsync/scripts/rrsync 2>/dev/null || true')
[ -n "$RRSYNC" ] || { echo "rrsync staat niet op de server (zit in het pakket rsync). Zonder rrsync richt ik niets in: dan zou de sleutel niet begrensd zijn." >&2; exit 1; }

BEKEND=$(ssh-keygen -F "$SERVER_HOST" | grep -v '^#' || true)
[ -n "$BEKEND" ] || { echo "Geen bekende serveridentiteit voor $SERVER_HOST in ~/.ssh/known_hosts." >&2; exit 1; }
# Niet-gehashte regels zodat de bouwmachine ze op adres kan terugvinden.
BEKEND=$(printf '%s\n' "$BEKEND" | awk -v h="$SERVER_HOST" '{print h" "$2" "$3}')

echo "2/4  Nieuwe sleutel maken…"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ssh-keygen -q -t ed25519 -N '' -C "$MERK" -f "$TMP/sleutel"

echo "3/4  Publieke helft op de server zetten (begrensd tot $SITE_PAD)…"
verwijder_oude_sleutel
REGEL="command=\"$RRSYNC -wo $SITE_PAD\",restrict $(cat "$TMP/sleutel.pub")"
printf '%s\n' "$REGEL" | ssh "$SSH_DOEL" 'umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys'

echo "     Proef: mag de sleutel een shell openen? (moet NEE zijn)"
if ssh -i "$TMP/sleutel" -o IdentitiesOnly=yes -o BatchMode=yes "$SERVER_USER@$SERVER_HOST" 'echo shell-open' 2>/dev/null | grep -q shell-open; then
  verwijder_oude_sleutel
  echo "De sleutel kon een shell openen — begrenzing werkt niet. Sleutel weer verwijderd." >&2; exit 1
fi
echo "     Nee — goed."

echo "4/4  GitHub inrichten…"
gh api -X PUT "repos/$REPO/environments/$OMGEVING" \
  -F "deployment_branch_policy[protected_branches]=false" \
  -F "deployment_branch_policy[custom_branch_policies]=true" >/dev/null
gh api -X POST "repos/$REPO/environments/$OMGEVING/deployment-branch-policies" -f name=main >/dev/null 2>&1 || true
gh secret set BLOG_DEPLOY_KEY --env "$OMGEVING" --repo "$REPO" < "$TMP/sleutel"
printf '%s\n' "$BEKEND" | gh secret set BLOG_KNOWN_HOSTS --env "$OMGEVING" --repo "$REPO"
gh variable set BLOG_DEPLOY_DOEL --env "$OMGEVING" --repo "$REPO" --body "$SERVER_USER@$SERVER_HOST"

echo
echo "Klaar. De privé-sleutel is lokaal gewist en staat alleen nog in GitHub."
echo "Proefdraaien:  gh workflow run publiceer-blog.yml --repo $REPO   (na het mergen van de workflow)"
