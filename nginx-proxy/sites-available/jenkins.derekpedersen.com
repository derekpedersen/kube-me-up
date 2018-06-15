server {
    listen 80;
    server_name jenkins.derekpedersen.com;
    return 301 https://$host$request_uri;
}
 
server {
    listen 443 ssl;
    server_name jenkins.derekpedersen.com;

    ssl_certificate /etc/ssl_cert/jenkins.derekpedersen.com/tls.crt;
    ssl_certificate_key /etc/ssl_cert/jenkins.derekpedersen.com/tls.key;
 
    location / {
        auth_basic "Restricted Content";
        auth_basic_user_file /etc/nginx/.htpasswd;

        proxy_pass http://jenkins-ui:8080/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}