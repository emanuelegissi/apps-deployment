# Reload unit generation (after any quadlet edits)
sudo systemctl daemon-reload

# Restart the podman network first
sudo systemctl restart apps-network.service

# Restart backends
sudo systemctl restart n8n.service
sudo systemctl restart redis.service
sudo systemctl restart minio.service
sudo systemctl restart dex.service
sudo systemctl restart grist.service

# Restart reverse proxy last
sudo systemctl restart caddy.service

# Quick check-up
systemctl --no-pager --full status apps-network n8n redis minio dex grist caddy
podman ps --format 'table {{.Names}}\t{{.Status}}\t{{.Networks}}\t{{.Ports}}'

# Check log
# sudo systemctl restart dex
# sudo journalctl -u dex -n 80 --no-pager
# 
