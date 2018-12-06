server {
    listen 80;
    server_name jupyter.derekpedersen.io;
    return 301 https://$host$request_uri;
}
 
server {
    listen 443 ssl;
    server_name jupyter.derekpedersen.io;

    ssl_certificate /etc/ssl_cert/jupyter.derekpedersen.io/tls.crt;
    ssl_certificate_key /etc/ssl_cert/jupyter.derekpedersen.io/tls.key;
 
    location / {
        #auth_basic "Restricted Content";
        #auth_basic_user_file /etc/nginx/.htpasswd;

        proxy_pass http://jupyter-hub-service:8000/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}