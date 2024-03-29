worker_processes 4;

events {
  worker_connections 500;
}

http {
  geo $limit {
    default 1;
  }
  map $limit $limit_key {
      0 "";
      1 $binary_remote_addr;
  }
  limit_req_zone $limit_key zone=LimitZoneAPI:10m rate=200r/s;

  map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
  }

  upstream prep-api {
    server ${PREP_URL}:9000;
  }

  log_format api_log 'Proxy IP: $remote_addr | Client IP: $http_x_forwarded_for | Time: $time_local' ' Request: "$request" | Status: $status | Bytes Sent: $body_bytes_sent | Referrer: "$http_referer"' ' User Agent: "$http_user_agent"';

  server {
    listen 9000;
    listen [::]:9000;

    access_log /var/log/nginx/access_api.log api_log;

    # Apply throtteling
    limit_req zone=LimitZoneAPI burst=50 delay=10;

    location / {
      # Apply blacklist
      include /etc/nginx/access_lists/api_blacklist.conf;
      allow all;

      # Forward traffic
      proxy_pass http://prep-api;
      proxy_set_header X-Forwarded-For $remote_addr;
      proxy_set_header X-Forwarded-Host $host;

      # Websocket support
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
    }
  }
}

stream {
  limit_conn_zone $binary_remote_addr zone=LimitZoneGRPC:10m;

  upstream prep-grpc {
    server ${PREP_URL}:7100;
  }

  log_format grpc_log 'Client IP: $remote_addr | Time: $time_local';

  server {
    listen 7100;
    listen [::]:7100;

    access_log /var/log/nginx/access_grpc.log grpc_log;

    # Apply throtteling
    limit_conn LimitZoneGRPC 100;

    # Apply whitelist
    #include /etc/nginx/access_lists/grpc_whitelist.conf;
    #deny all;

    # Forward traffic
    proxy_pass prep-grpc;
  }
}
