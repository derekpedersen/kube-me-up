server {
    listen 80;
    server_name jenkins.derekpedersen.com;
	return 301 https://jenkins.derekpedersen.io$request_uri;
}
 
server {
    listen 443 ssl;

    ssl_certificate /etc/ssl_cert/jenkins.derekpedersen.com/tls.crt;
    ssl_certificate_key /etc/ssl_cert/jenkins.derekpedersen.com/tls.key;

    server_name jenkins.derekpedersen.com;
	return 301 https://jenkins.derekpedersen.io$request_uri;
}