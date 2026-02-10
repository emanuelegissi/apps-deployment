sudo systemctl stop apps-network.service
sudo systemctl stop n8n.service
sudo systemctl stop redis.service
sudo systemctl stop minio.service
sudo systemctl stop dex.service
sudo systemctl stop grist.service
sudo systemctl stop caddy.service

# Quick check-up
systemctl --no-pager --full status apps-network n8n redis minio dex grist caddy
podman ps --format 'table {{.Names}}\t{{.Status}}\t{{.Networks}}\t{{.Ports}}'

